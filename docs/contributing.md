# Contributing Guidelines

This document provides guidelines for contributing to the PXE Boot Server project.

## Development Setup

### Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- Git
- Bash/shell environment

### Local Development

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd pxe-boot
   ```

2. **Set up development environment:**
   ```bash
   cp .env.example .env
   # Edit .env for your development settings
   ```

3. **Build and run:**
   ```bash
   docker-compose up -d --build
   ```

4. **Verify setup:**
   ```bash
   curl http://localhost:8080/health
   docker-compose logs -f
   ```

## Development Workflow

### Branching Strategy

- `main`: Production-ready code
- `develop`: Integration branch for features
- `feature/*`: Feature branches
- `bugfix/*`: Bug fix branches
- `hotfix/*`: Critical fixes for production

### Commit Messages

Follow conventional commit format:

```
type(scope): description

[optional body]

[optional footer]
```

Types:
- `feat`: New features
- `fix`: Bug fixes
- `docs`: Documentation changes
- `style`: Code style changes
- `refactor`: Code refactoring
- `test`: Testing related changes
- `chore`: Maintenance tasks

Examples:
```
feat(dhcp): add support for DHCP option 82
fix(healthcheck): resolve TFTP check failure
docs(installation): update prerequisites section
```

### Pull Request Process

1. **Create feature branch:**
   ```bash
   git checkout -b feature/my-feature
   ```

2. **Make changes and test:**
   ```bash
   # Run tests
   docker-compose -f docker-compose.test.yml up --abort-on-container-exit

   # Manual testing
   docker-compose up -d
   ./scripts/healthcheck.sh
   ```

3. **Commit changes:**
   ```bash
   git add .
   git commit -m "feat: add new feature"
   ```

4. **Push and create PR:**
   ```bash
   git push origin feature/my-feature
   # Create pull request on GitHub
   ```

5. **Code review and merge**

## Code Standards

### Shell Scripts

- Use Bash 4.0+ compatible syntax
- Include error handling with `set -e`
- Add logging for important operations
- Use descriptive variable names
- Include function comments

**Script template:**
```bash
#!/bin/bash
# Brief description of script purpose

set -e

# Constants
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/var/log/pxe/${SCRIPT_NAME}.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Main function
main() {
    log "Starting ${SCRIPT_NAME}"

    # Implementation here

    log "Completed ${SCRIPT_NAME}"
}

# Run main function
main "$@"
```

### Docker Configuration

- Use multi-stage builds for optimization
- Include security best practices
- Document all exposed ports and volumes
- Use specific image tags (avoid `latest`)

### Configuration Files

- Use environment variable substitution
- Include comments explaining complex options
- Validate syntax in CI/CD
- Keep sensitive data out of version control

## Testing

### Unit Tests

```bash
# Run shell script syntax checks
find scripts/ -name "*.sh" -exec bash -n {} \;

# Test configuration file syntax
docker-compose config
```

### Integration Tests

```bash
# Build test environment
docker-compose -f docker-compose.test.yml build

# Run integration tests
docker-compose -f docker-compose.test.yml up --abort-on-container-exit
```

### Manual Testing Checklist

- [ ] DHCP server assigns IPs correctly
- [ ] HTTP server serves PXE files
- [ ] PXE boot menu displays
- [ ] OS image downloads work
- [ ] Health checks pass
- [ ] Logs are properly formatted
- [ ] Backup/restore functions correctly

## Documentation

### Documentation Standards

- Use Markdown format
- Include table of contents for long documents
- Provide code examples with syntax highlighting
- Keep screenshots updated
- Test all commands in documentation

### Documentation Structure

```
docs/
├── README.md              # Project overview
├── installation.md        # Installation guide
├── configuration.md       # Configuration reference
├── operations.md          # Operations manual
├── security.md           # Security guide
├── troubleshooting.md    # Troubleshooting guide
└── contributing.md       # This file
```

### Updating Documentation

1. **For code changes:** Update relevant documentation
2. **For new features:** Add documentation before merging
3. **For bug fixes:** Update troubleshooting guides if needed
4. **Regular reviews:** Keep documentation current with code

## Security Considerations

### Code Security

- Never commit sensitive data (passwords, keys, tokens)
- Use environment variables for configuration
- Implement proper input validation
- Follow principle of least privilege

### Reporting Security Issues

1. **Do not create public issues** for security vulnerabilities
2. **Email maintainers** directly with details
3. **Allow time** for fix before public disclosure
4. **Follow responsible disclosure** practices

## Release Process

### Version Numbering

Follow semantic versioning (MAJOR.MINOR.PATCH):

- **MAJOR:** Breaking changes
- **MINOR:** New features (backward compatible)
- **PATCH:** Bug fixes (backward compatible)

### Release Checklist

- [ ] Update version in Docker labels
- [ ] Update CHANGELOG.md
- [ ] Tag release in git
- [ ] Build and push Docker images
- [ ] Update documentation
- [ ] Announce release

### Release Commands

```bash
# Tag release
git tag -a v1.2.3 -m "Release version 1.2.3"
git push origin v1.2.3

# Build and push images
docker build -t pxe-server:v1.2.3 -t pxe-server:latest .
docker push pxe-server:v1.2.3
docker push pxe-server:latest
```

## Code Review Guidelines

### Review Checklist

**For reviewers:**
- [ ] Code follows project standards
- [ ] Tests are included and pass
- [ ] Documentation is updated
- [ ] Security implications considered
- [ ] Performance impact assessed
- [ ] Breaking changes clearly documented

**For contributors:**
- [ ] Self-review code before requesting review
- [ ] Provide context for changes
- [ ] Respond promptly to review feedback
- [ ] Make requested changes clearly

### Review Process

1. **Automated checks** (CI/CD) pass
2. **Peer review** by at least one maintainer
3. **Approval** and merge by maintainer
4. **Post-merge** monitoring for issues

## Community Guidelines

### Communication

- Be respectful and inclusive
- Use clear, concise language
- Provide context for questions
- Help others when possible

### Issue Reporting

**Bug reports should include:**
- Clear title describing the issue
- Steps to reproduce
- Expected vs actual behavior
- Environment details (OS, Docker versions)
- Relevant log output

**Feature requests should include:**
- Clear description of the feature
- Use case or problem it solves
- Proposed implementation if applicable
- Alternative solutions considered

### Support

- Check existing documentation first
- Search existing issues
- Provide detailed information when asking for help
- Be patient waiting for responses

## Recognition

Contributors will be recognized in:
- Git commit history
- CHANGELOG.md for significant contributions
- GitHub contributors list
- Release notes

## License

By contributing to this project, you agree that your contributions will be licensed under the same license as the project (MIT License).
