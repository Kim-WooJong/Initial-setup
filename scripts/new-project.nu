#!/usr/bin/env nu

const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command command-failure-message]

def project-path [
    base: string
    name: string
] {
    let root = (
        if ($base | is-empty) {
            $env.PWD
        } else {
            $base | path expand
        }
    )

    $root | path join $name
}

def init-git [dir: path] {
    if (which git | is-empty) {
        return
    }

    let args = [
        "-C"
        ($dir | into string)
        "init"
    ]

    let result = (run-command "git" $args --live)
    if not $result.ok {
        error make { msg: (command-failure-message "git init" $result) }
    }
}

def create-common [dir: path name: string] {
    mkdir $dir

    if not (($dir | path join "README.md") | path exists) {
        ("# " + $name + (char nl)) | save ($dir | path join "README.md")
    }
}

def create-rust [dir: path name: string] {
    if (which cargo | is-empty) {
        error make {
            msg: "cargo is required for a Rust project."
        }
    }

    let parent = ($dir | path dirname)
    mkdir $parent

    let args = [
        "new"
        ($dir | into string)
    ]

    let result = (run-command "cargo" $args --live)
    if not $result.ok {
        error make { msg: (command-failure-message "cargo new" $result) }
    }
}

def create-julia [dir: path name: string] {
    create-common $dir $name

    mkdir ($dir | path join "src")
    mkdir ($dir | path join "test")

    [
        ("name = \"" + $name + "\"")
        'version = "0.1.0"'
        ""
        "[deps]"
        ""
    ]
    | str join (char nl)
    | save ($dir | path join "Project.toml")

    [
        "function main()"
        ("    println(\"" + $name + "\")")
        "end"
        ""
        "main()"
        ""
    ]
    | str join (char nl)
    | save ($dir | path join "src" "main.jl")

    [
        "using Test"
        ""
        '@test true'
        ""
    ]
    | str join (char nl)
    | save ($dir | path join "test" "runtests.jl")

    [
        ".julia/"
        "Manifest.toml"
        ""
    ]
    | str join (char nl)
    | save ($dir | path join ".gitignore")

    init-git $dir
}

def create-python [dir: path name: string] {
    create-common $dir $name

    mkdir ($dir | path join "src")
    mkdir ($dir | path join "tests")

    [
        "[project]"
        ("name = \"" + $name + "\"")
        'version = "0.1.0"'
        'requires-python = ">=3.11"'
        ""
        "[build-system]"
        'requires = ["setuptools>=68"]'
        'build-backend = "setuptools.build_meta"'
        ""
    ]
    | str join (char nl)
    | save ($dir | path join "pyproject.toml")

    "" | save ($dir | path join "src" "__init__.py")
    "__pycache__/\n.venv/\n" | save ($dir | path join ".gitignore")

    init-git $dir
}

def create-generic [dir: path name: string] {
    create-common $dir $name
    ".env\n" | save ($dir | path join ".gitignore")
    init-git $dir
}

def main [
    kind: string
    name: string
    --path: string = ""
] {
    let dir = (project-path $path $name)

    if ($dir | path exists) {
        error make {
            msg: ("Target already exists: " + ($dir | into string))
        }
    }

    match $kind {
        "rust" => {
            create-rust $dir $name
        }

        "julia" => {
            create-julia $dir $name
        }

        "python" => {
            create-python $dir $name
        }

        "generic" => {
            create-generic $dir $name
        }

        _ => {
            error make {
                msg: "Use rust, julia, python, or generic."
            }
        }
    }

    print ("[ok] Project created: " + ($dir | into string))
}
