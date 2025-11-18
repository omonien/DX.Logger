# Contributing to DX.Logger

First off, thank you for considering contributing to DX.Logger! It's people like you that make DX.Logger such a great tool.

## Code of Conduct

This project and everyone participating in it is governed by respect and professionalism. By participating, you are expected to uphold this standard.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the existing issues to avoid duplicates. When you create a bug report, include as many details as possible using the bug report template.

**Good bug reports include:**
- A clear and descriptive title
- Exact steps to reproduce the problem
- Expected vs. actual behavior
- Code samples
- Your environment (Delphi version, platform, etc.)

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, use the feature request template and include:
- A clear and descriptive title
- A detailed description of the proposed feature
- Use cases and examples
- Why this enhancement would be useful

### Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Follow the coding standards** (see below)
3. **Add tests** for new features
4. **Update documentation** as needed
5. **Ensure all tests pass**
6. **Submit a pull request** using the PR template

## Development Setup

### Prerequisites
- Delphi 10.3 or later
- Git

### Getting Started

```bash
# Clone your fork
git clone https://github.com/YOUR-USERNAME/DX.Logger.git
cd DX.Logger

# Add upstream remote
git remote add upstream https://github.com/omonien/DX.Logger.git

# Create a branch for your changes
git checkout -b feature/my-new-feature
```

### Running Tests

```bash
cd tests
dcc32 DX.Logger.Tests.dpr
DX.Logger.Tests.exe
```

All tests should pass before submitting a PR.

## Coding Standards

This project follows the [Delphi Style Guide](docs/Delphi%20Style%20Guide%20EN.md). Key points:

### Naming Conventions
- **Classes**: `T` prefix + PascalCase (e.g., `TMyClass`)
- **Interfaces**: `I` prefix + PascalCase (e.g., `ILogger`)
- **Local variables**: `L` prefix + PascalCase (e.g., `LResult`)
- **Fields**: `F` prefix + PascalCase (e.g., `FConnection`)
- **Parameters**: `A` prefix + PascalCase (e.g., `AMessage`)
- **Constants**: `C_` prefix + UPPER_SNAKE_CASE (e.g., `C_MAX_SIZE`)

### Formatting
- **Indentation**: 2 spaces (no tabs)
- **Line length**: Maximum 120 characters
- **Encoding**: UTF-8 with BOM
- **Line endings**: CRLF (Windows style)

### Code Quality
- Write self-documenting code
- Add comments for complex logic
- Use `///` for documentation comments
- No global variables
- Always use `try..finally` for resource management

### License Headers

All source files must include the SPDX license header. See [docs/LICENSE_HEADERS.md](docs/LICENSE_HEADERS.md) for details.

```delphi
unit My.Unit.Name;

{
  My.Unit.Name - Brief description

  Copyright (c) 2025 Olaf Monien
  SPDX-License-Identifier: MIT
}

interface

type
  TMyClass = class
  private
    FName: string;
  public
    constructor Create(const AName: string);
    procedure DoSomething;
  end;

implementation

{ TMyClass }

constructor TMyClass.Create(const AName: string);
begin
  FName := AName;
end;

procedure TMyClass.DoSomething;
var
  LResult: Integer;
begin
  LResult := 42;
  // Implementation here
end;

end.
```

## Security

**Never commit sensitive data!**
- No API keys, passwords, or tokens in code
- Use `config.local.ini` for local credentials
- Check `.gitignore` before committing
- See [SECURITY.md](SECURITY.md) for details

## Documentation

- Update README.md if you change functionality
- Update relevant documentation in `docs/`
- Add XML documentation comments for public APIs
- Update CHANGELOG.md

## Commit Messages

Write clear, concise commit messages:

```
feat: Add support for custom log formatters
fix: Resolve thread safety issue in file provider
docs: Update Seq provider configuration guide
test: Add tests for log level filtering
refactor: Simplify provider registration logic
```

Prefixes:
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `test:` - Test changes
- `refactor:` - Code refactoring
- `perf:` - Performance improvements
- `chore:` - Maintenance tasks

## Questions?

Feel free to open a discussion on GitHub if you have questions about contributing.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

All source files must include the MIT license header. See [docs/LICENSE_HEADERS.md](docs/LICENSE_HEADERS.md) for the required format and best practices.

