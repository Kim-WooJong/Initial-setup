using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.ServiceProcess;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;

// Build using the Windows .NET Framework compiler; C# 5 compatible.
internal sealed class WireGuardSync : ServiceBase
{
    const string ServiceId = "InitialSetupWireGuardSync";
    const string PipeId = "InitialSetup.WireGuardSync.v1";
    const int Limit = 8 * 1024 * 1024;
    static readonly SecurityIdentifier SystemSid = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
    static readonly SecurityIdentifier AdminSid = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
    static readonly string InstallRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "InitialSetup", "WireGuardSync");
    static readonly string Store = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "WireGuard", "Data", "Configurations");
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = Limit, RecursionLimit = 12 };
    volatile bool stopping;
    NamedPipeServerStream current;
    Thread worker;

    [StructLayout(LayoutKind.Sequential)] struct Blob { public int Length; public IntPtr Data; }
    [DllImport("crypt32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CryptProtectData(ref Blob input, string description, IntPtr entropy, IntPtr reserved, IntPtr prompt, uint flags, out Blob output);
    [DllImport("crypt32.dll", SetLastError = true)]
    static extern bool CryptUnprotectData(ref Blob input, out IntPtr description, IntPtr entropy, IntPtr reserved, IntPtr prompt, uint flags, out Blob output);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr ptr);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool GetNamedPipeClientComputerName(IntPtr pipe, StringBuilder name, uint length);

    static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "service") {
            if (!WindowsIdentity.GetCurrent().User.Equals(SystemSid)) return 1;
            ServiceBase.Run(new WireGuardSync()); return 0;
        }
        try { Client(args); return 0; }
        catch { Console.Error.WriteLine("WireGuard helper failed; configuration contents were not logged."); return 1; }
    }
    WireGuardSync() { ServiceName = ServiceId; CanStop = true; AutoLog = false; }
    protected override void OnStart(string[] args) {
        // Fail startup before accepting traffic if policy is invalid.
        Policy();
        worker = new Thread(ServerLoop); worker.IsBackground = true; worker.Start();
    }
    protected override void OnStop() { stopping = true; if (current != null) current.Dispose(); }

    static Dictionary<string, object> Object(object value) {
        var result = value as Dictionary<string, object>; if (result == null) throw new InvalidDataException(); return result;
    }
    static string Str(Dictionary<string, object> value, string key) {
        object item; if (!value.TryGetValue(key, out item) || !(item is string)) throw new InvalidDataException(); return (string)item;
    }
    static void Schema(Dictionary<string, object> value) {
        object version; if (!value.TryGetValue("schema_version", out version) || !(version is int) || (int)version != 1) throw new InvalidDataException();
    }
    static object[] ArrayValue(Dictionary<string, object> value, string key) {
        object item; if (!value.TryGetValue(key, out item)) throw new InvalidDataException();
        var array = item as object[]; if (array == null) throw new InvalidDataException(); return array;
    }
    static string[] Names(Dictionary<string, object> value) {
        var names = ArrayValue(value, "tunnels").Select(x => x as string).ToArray();
        if (names.Length == 0 || names.Length > 128 || names.Any(x => x == null || !Regex.IsMatch(x, @"\A[A-Za-z0-9_=+.-]{1,15}\z") || x == "." || x == "..") || names.Distinct(StringComparer.OrdinalIgnoreCase).Count() != names.Length) throw new InvalidDataException();
        return names;
    }
    static Dictionary<string, object> ReadJson(string path) {
        if (new FileInfo(path).Length > Limit) throw new InvalidDataException();
        return Object(Json.DeserializeObject(File.ReadAllText(path, new UTF8Encoding(false, true))));
    }
    static Dictionary<string, object> Policy() {
        string file = Path.Combine(InstallRoot, "policy.json"); NoReparse(file);
        var p = ReadJson(file); Schema(p); Names(p);
        if (!Regex.IsMatch(Str(p, "device_id"), @"\A[A-Za-z0-9][A-Za-z0-9_-]{0,40}\z")) throw new InvalidDataException();
        new SecurityIdentifier(Str(p, "caller_sid")); return p;
    }
    static void NoReparse(string path) {
        string full = Path.GetFullPath(path);
        for (string part = full; part != null; part = Path.GetDirectoryName(part)) {
            if ((File.Exists(part) || Directory.Exists(part)) && (File.GetAttributes(part) & FileAttributes.ReparsePoint) != 0) throw new UnauthorizedAccessException();
        }
    }
    static FileSecurity FileAcl(SecurityIdentifier user) {
        var acl = new FileSecurity(); acl.SetAccessRuleProtection(true, false); acl.SetOwner(user);
        acl.AddAccessRule(new FileSystemAccessRule(user, FileSystemRights.FullControl, AccessControlType.Allow));
        if (!user.Equals(SystemSid)) acl.AddAccessRule(new FileSystemAccessRule(SystemSid, FileSystemRights.FullControl, AccessControlType.Allow));
        return acl;
    }
    static void PrivateParent(string path) {
        if (!Path.IsPathRooted(path) || path.StartsWith(@"\\", StringComparison.Ordinal) || path.IndexOf(':', 2) >= 0 || Path.GetFullPath(path) != path) throw new InvalidDataException();
        NoReparse(path);
        var parent = new DirectoryInfo(Path.GetDirectoryName(path));
        var acl = parent.GetAccessControl(); var user = WindowsIdentity.GetCurrent().User;
        if (!acl.AreAccessRulesProtected) throw new UnauthorizedAccessException();
        var owner = (SecurityIdentifier)acl.GetOwner(typeof(SecurityIdentifier));
        if (!owner.Equals(user) && !owner.Equals(SystemSid) && !owner.Equals(AdminSid)) throw new UnauthorizedAccessException();
        var write = FileSystemRights.ReadData | FileSystemRights.Write | FileSystemRights.Delete | FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership | FileSystemRights.DeleteSubdirectoriesAndFiles;
        foreach (FileSystemAccessRule rule in acl.GetAccessRules(true, true, typeof(SecurityIdentifier))) {
            var sid = (SecurityIdentifier)rule.IdentityReference;
            if (rule.AccessControlType == AccessControlType.Allow && (rule.FileSystemRights & write) != 0 && !sid.Equals(user) && !sid.Equals(SystemSid) && !sid.Equals(AdminSid)) throw new UnauthorizedAccessException();
        }
    }
    static void PrivateWrite(string path, byte[] data, SecurityIdentifier user) {
        NoReparse(path);
        // Never truncate an existing user-selected file, link or response.
        using (var stream = new FileStream(path, FileMode.CreateNew, FileSystemRights.Write, FileShare.None, 4096, FileOptions.WriteThrough, FileAcl(user))) {
            stream.Write(data, 0, data.Length); stream.Flush(true);
        }
    }
    static byte[] Encode(object value) { return new UTF8Encoding(false, true).GetBytes(Json.Serialize(value)); }
    static void WriteFrame(Stream stream, object value) {
        byte[] data = Encode(value); if (data.Length > Limit) throw new InvalidDataException();
        var size = BitConverter.GetBytes(data.Length); stream.Write(size, 0, 4); stream.Write(data, 0, data.Length); stream.Flush();
        Array.Clear(data, 0, data.Length);
    }
    static byte[] ReadExactly(Stream stream, int size) {
        var bytes = new byte[size]; int offset = 0;
        while (offset < size) { int n = stream.Read(bytes, offset, size - offset); if (n == 0) throw new EndOfStreamException(); offset += n; }
        return bytes;
    }
    static Dictionary<string, object> ReadFrame(Stream stream) {
        int size = BitConverter.ToInt32(ReadExactly(stream, 4), 0); if (size <= 0 || size > Limit) throw new InvalidDataException();
        var data = ReadExactly(stream, size);
        try { return Object(Json.DeserializeObject(new UTF8Encoding(false, true).GetString(data))); }
        finally { Array.Clear(data, 0, data.Length); }
    }
    static void Client(string[] args) {
        if (args.Length != 5 || args[1] != "--request" || args[3] != "--response" || !new[] { "capture", "validate", "restore" }.Contains(args[0])) throw new ArgumentException();
        PrivateParent(args[2]); PrivateParent(args[4]);
        if (File.Exists(args[4])) throw new IOException();
        var request = ReadJson(args[2]); Schema(request); Names(request);
        string bundlePath = Str(request, "bundle_path"); PrivateParent(bundlePath);
        if (args[0] == "capture" && File.Exists(bundlePath)) throw new IOException();
        // Privileged server never receives any client-controlled filesystem path.
        var wire = new Dictionary<string, object> { { "schema_version", 1 }, { "action", args[0] }, { "device_id", Str(request, "device_id") }, { "tunnels", request["tunnels"] } };
        if (args[0] != "capture") wire["bundle"] = ReadJson(bundlePath);
        if (args[0] == "restore") wire["baseline"] = Object(request["baseline"]);
        using (var pipe = new NamedPipeClientStream(".", PipeId, PipeDirection.InOut, PipeOptions.None, TokenImpersonationLevel.Impersonation)) {
            pipe.Connect(10000);
            // A same-user pipe squatter cannot give its pipe SYSTEM ownership.
            if (!pipe.GetAccessControl().GetOwner(typeof(SecurityIdentifier)).Equals(SystemSid)) throw new UnauthorizedAccessException();
            WriteFrame(pipe, wire); var response = ReadFrame(pipe);
            object ok; if (!response.TryGetValue("ok", out ok) || !(ok is bool)) throw new IOException();
            if (!(bool)ok) { PrivateWrite(args[4], Encode(response), WindowsIdentity.GetCurrent().User); throw new IOException(); }
            if (args[0] == "capture") { PrivateWrite(bundlePath, Encode(response["bundle"]), WindowsIdentity.GetCurrent().User); response.Remove("bundle"); }
            PrivateWrite(args[4], Encode(response), WindowsIdentity.GetCurrent().User);
        }
    }
    void ServerLoop() {
        while (!stopping) {
            try {
                var policy = Policy(); var allowed = new SecurityIdentifier(Str(policy, "caller_sid"));
                var acl = new PipeSecurity(); acl.SetAccessRuleProtection(true, false); acl.SetOwner(SystemSid);
                acl.AddAccessRule(new PipeAccessRule(SystemSid, PipeAccessRights.FullControl, AccessControlType.Allow));
                acl.AddAccessRule(new PipeAccessRule(allowed, PipeAccessRights.ReadWrite | PipeAccessRights.ReadPermissions, AccessControlType.Allow));
                using (var pipe = new NamedPipeServerStream(PipeId, PipeDirection.InOut, 1, PipeTransmissionMode.Byte, PipeOptions.None, 4096, 4096, acl)) {
                    current = pipe; pipe.WaitForConnection();
                    using (var deadline = new Timer(delegate(object state) { try { pipe.Dispose(); } catch { } }, null, 30000, Timeout.Infinite)) {
                        try {
                            var computer = new StringBuilder(256);
                            if (!GetNamedPipeClientComputerName(pipe.SafePipeHandle.DangerousGetHandle(), computer, 256) || !String.Equals(computer.ToString().TrimStart('\\'), Environment.MachineName, StringComparison.OrdinalIgnoreCase)) throw new UnauthorizedAccessException();
                            // Impersonation uses the security context of the last message read.
                            // Read only bounded data before authenticating; dispatch remains after it.
                            var request = ReadFrame(pipe);
                            SecurityIdentifier caller = null;
                            pipe.RunAsClient(delegate { caller = WindowsIdentity.GetCurrent().User; });
                            if (caller == null || !caller.Equals(allowed)) throw new UnauthorizedAccessException();
                            var response = Dispatch(request, policy); WriteFrame(pipe, response);
                        } catch { try { WriteFrame(pipe, new { ok = false, error = "operation_failed" }); } catch { } }
                    }
                }
            } catch { if (!stopping) Thread.Sleep(1000); }
            finally { current = null; }
        }
    }
    static void CheckDescription(string name, string description) {
        if (!String.Equals(name, description, StringComparison.Ordinal)) throw new CryptographicException();
    }
    static byte[] Dpapi(byte[] input, string name, bool protect) {
        var source = new Blob { Length = input.Length, Data = Marshal.AllocHGlobal(input.Length) }; Blob output;
        IntPtr description = IntPtr.Zero;
        try {
            Marshal.Copy(input, 0, source.Data, input.Length);
            bool ok = protect ? CryptProtectData(ref source, name, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 1, out output) : CryptUnprotectData(ref source, out description, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 1, out output);
            if (!ok) throw new CryptographicException();
            try {
                if (!protect) CheckDescription(name, description == IntPtr.Zero ? null : Marshal.PtrToStringUni(description));
                var result = new byte[output.Length]; Marshal.Copy(output.Data, result, 0, result.Length); return result; }
            finally { for (int i = 0; i < output.Length; i++) Marshal.WriteByte(output.Data, i, 0); LocalFree(output.Data); }
        } finally { if (description != IntPtr.Zero) LocalFree(description); for (int i = 0; i < source.Length; i++) Marshal.WriteByte(source.Data, i, 0); Marshal.FreeHGlobal(source.Data); }
    }
    static string TunnelPath(string name) { string path = Path.Combine(Store, name + ".conf.dpapi"); NoReparse(path); return path; }
    static void Inactive(string[] names) {
        var wanted = new HashSet<string>(names.Select(name => "WireGuardTunnel$" + name), StringComparer.OrdinalIgnoreCase);
        foreach (var service in ServiceController.GetServices()) {
            using (service) { if (wanted.Contains(service.ServiceName) && service.Status != ServiceControllerStatus.Stopped) throw new InvalidOperationException(); }
        }
    }
    static Dictionary<string, string> Bundle(Dictionary<string, object> bundle, string device, string[] names) {
        Schema(bundle); if (Str(bundle, "device_id") != device) throw new InvalidDataException();
        var configs = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var value in ArrayValue(bundle, "tunnels")) {
            var item = Object(value); string name = Str(item, "name"), config = Str(item, "config");
            if (!names.Contains(name) || configs.ContainsKey(name) || config.Length == 0 || config.Length > 1024 * 1024 || config.IndexOf('\0') >= 0 || !Regex.IsMatch(config, @"(?m)^\s*\[Interface\]\s*\r?$")) throw new InvalidDataException();
            configs.Add(name, config);
        }
        if (configs.Count != names.Length) throw new InvalidDataException(); return configs;
    }
    // Ciphertext fingerprints intentionally avoid decrypting during preflight.
    static string Fingerprint(byte[] bytes) {
        using (var hash = SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant();
    }
    static Dictionary<string, object> Baseline(string[] names) {
        var result = new Dictionary<string, object>(StringComparer.Ordinal);
        foreach (string name in names) {
            string path = TunnelPath(name);
            if (!File.Exists(path)) { result.Add(name, "missing"); continue; }
            if (new FileInfo(path).Length > 1024 * 1024) throw new InvalidDataException();
            result.Add(name, Fingerprint(File.ReadAllBytes(path)));
        }
        return result;
    }
    static void SameBaseline(Dictionary<string, object> expected, Dictionary<string, object> actual) {
        if (expected.Count != actual.Count) throw new InvalidDataException();
        foreach (var item in actual) {
            object value;
            if (!expected.TryGetValue(item.Key, out value) || !(value is string) || !String.Equals((string)value, (string)item.Value, StringComparison.Ordinal)) throw new InvalidOperationException();
        }
    }
    static object Dispatch(Dictionary<string, object> request, Dictionary<string, object> policy) {
        Schema(request); var names = Names(request); var expected = Names(policy);
        string device = Str(request, "device_id"), action = Str(request, "action");
        if (device != Str(policy, "device_id") || !names.OrderBy(x => x, StringComparer.Ordinal).SequenceEqual(expected.OrderBy(x => x, StringComparer.Ordinal))) throw new UnauthorizedAccessException();
        NoReparse(Store); foreach (string name in names) TunnelPath(name);
        if (action == "capture") {
            var items = new List<object>();
            var baseline = new Dictionary<string, object>(StringComparer.Ordinal);
            foreach (string name in names) {
                if (!File.Exists(TunnelPath(name))) { baseline.Add(name, "missing"); continue; }
                if (new FileInfo(TunnelPath(name)).Length > 1024 * 1024) throw new InvalidDataException();
                byte[] encrypted = File.ReadAllBytes(TunnelPath(name));
                baseline.Add(name, Fingerprint(encrypted));
                byte[] plain = Dpapi(encrypted, name, false);
                try { items.Add(new { name = name, config = new UTF8Encoding(false, true).GetString(plain) }); }
                finally { Array.Clear(plain, 0, plain.Length); }
            }
            SameBaseline(baseline, Baseline(names));
            return new { ok = true, baseline = baseline, bundle = new { schema_version = 1, device_id = device, tunnels = items } };
        }
        var configs = Bundle(Object(request["bundle"]), device, names);
        Inactive(names);
        if (action == "validate") return new { ok = true, baseline = Baseline(names) };
        if (action != "restore") throw new InvalidDataException();
        var original = Object(request["baseline"]);
        SameBaseline(original, Baseline(names));
        string recovery = Path.Combine(Store, "initial-setup-recovery-" + Guid.NewGuid().ToString("N"));
        var directoryAcl = new DirectorySecurity(); directoryAcl.SetAccessRuleProtection(true, false); directoryAcl.SetOwner(SystemSid);
        directoryAcl.AddAccessRule(new FileSystemAccessRule(SystemSid, FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        Directory.CreateDirectory(recovery, directoryAcl);
        var replaced = new List<string>();
        var existed = new HashSet<string>(StringComparer.Ordinal);
        try {
            foreach (string name in names) {
                if (File.Exists(TunnelPath(name))) {
                    if (new FileInfo(TunnelPath(name)).Length > 1024 * 1024) throw new InvalidDataException();
                    existed.Add(name);
                    PrivateWrite(Path.Combine(recovery, name + ".conf.dpapi"), File.ReadAllBytes(TunnelPath(name)), SystemSid);
                }
                byte[] plain = new UTF8Encoding(false, true).GetBytes(configs[name]);
                try { PrivateWrite(Path.Combine(recovery, name + ".new"), Dpapi(plain, name, true), SystemSid); }
                finally { Array.Clear(plain, 0, plain.Length); }
            }
            PrivateWrite(Path.Combine(recovery, "manifest.json"), Encode(new { schema_version = 1, device_id = device, tunnels = names, existed = existed.ToArray() }), SystemSid);
            // Recheck immediately before commit; do not activate or stop services.
            Inactive(names);
            SameBaseline(original, Baseline(names));
            foreach (string name in names) {
                if (existed.Contains(name)) File.Replace(Path.Combine(recovery, name + ".new"), TunnelPath(name), null);
                else File.Move(Path.Combine(recovery, name + ".new"), TunnelPath(name));
                replaced.Add(name);
            }
            return new { ok = true, recovery = recovery };
        } catch {
            bool rolledBack = true;
            foreach (string name in replaced.AsEnumerable().Reverse()) {
                try {
                    if (!existed.Contains(name)) { File.Delete(TunnelPath(name)); continue; }
                    string temp = Path.Combine(recovery, name + ".rollback");
                    PrivateWrite(temp, File.ReadAllBytes(Path.Combine(recovery, name + ".conf.dpapi")), SystemSid);
                    File.Replace(temp, TunnelPath(name), null);
                } catch { rolledBack = false; }
            }
            return new { ok = false, error = rolledBack ? "restore_failed_rolled_back" : "restore_failed_recovery_required", recovery = recovery };
        }
    }
}
