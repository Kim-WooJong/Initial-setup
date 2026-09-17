# Development and Testing

Run the project validation from the repository root:

```nu
nu setup.nu --check
```

For diagnostic-only entry checks:

```nu
nu setup.nu --diagnose
```

Important regression areas are entry-point routing, partial archive rejection, lock behavior, provider-head concurrency, Cloud-wins plan/apply/rollback, and command-reference coverage. Keep long-lived testing guidance here instead of creating per-version testing documents.
