# Security Policy

## Reporting Security Vulnerabilities

If you discover a security vulnerability in DX.Logger, please report it by emailing **olaf@monien.net**. 

Please do **not** open a public issue for security vulnerabilities.

## Secure Configuration Management

### Protecting Sensitive Data

This project uses configuration files to manage sensitive data like API keys and server URLs. Follow these guidelines:

### ✅ Best Practices

1. **Never commit sensitive data**
   - Use `config.local.ini` for your credentials (already in `.gitignore`)
   - Only commit `config.example.ini` with placeholder values

2. **Use environment-specific configurations**
   - Development: `config.local.ini`
   - Production: Environment variables or secure vaults
   - CI/CD: GitHub Secrets or similar

3. **Rotate credentials regularly**
   - Change API keys periodically
   - Revoke unused or compromised keys immediately

4. **Limit access**
   - Only share credentials with authorized team members
   - Use separate credentials for different environments

### ❌ What NOT to Do

- ❌ Never hardcode API keys in source code
- ❌ Never commit `*.local.ini` files
- ❌ Never share credentials in chat, email, or documentation
- ❌ Never use production credentials in development/testing
- ❌ Never commit credentials in comments or commit messages

## Files Protected by .gitignore

The following patterns are automatically ignored:

```
config.local.ini
*.local.ini
.env.local
```

## GitHub Security Features

This repository benefits from:

- **Secret Scanning**: GitHub automatically scans for known secret patterns
- **Push Protection**: Prevents accidental commits of secrets (when enabled)
- **Dependabot**: Monitors dependencies for security vulnerabilities

## For Contributors

Before committing:

1. ✅ Check that no sensitive data is in your changes
2. ✅ Verify `config.local.ini` is not staged
3. ✅ Use placeholder values in examples
4. ✅ Review the diff before pushing

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| Latest  | ✅ Yes             |
| Older   | ❌ No              |

We only provide security updates for the latest version.

## Additional Resources

- [docs/CONFIGURATION.md](docs/CONFIGURATION.md) - Detailed configuration guide
- [docs/SEQ_PROVIDER.md](docs/SEQ_PROVIDER.md) - Seq provider documentation
- [GitHub Security Best Practices](https://docs.github.com/en/code-security)
- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)

## License

This security policy is part of the DX.Logger project and is covered by the MIT License.

