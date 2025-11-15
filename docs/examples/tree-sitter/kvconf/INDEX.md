# Tree-sitter KVConf Examples Index

This directory contains code examples, sample configurations, and usage demonstrations for the tree-sitter kvconf project.

## Configuration Examples

### Environment Files
- [basic-env-file.env](./basic-env-file.env) - Complete .env file with common patterns
- [value-types.env](./value-types.env) - Demonstrates all supported value types

### NPM Configuration
- [complete-npmrc.npmrc](./complete-npmrc.npmrc) - Comprehensive .npmrc with all features

### Java Properties
- [java-properties.properties](./java-properties.properties) - Enterprise Java application config

### INI Configuration
- [config.ini](./config.ini) - Multi-section INI file with comments

## Parser Feature Examples

### Value Types and Edge Cases
- [value-types.env](./value-types.env) - All supported value types with examples
- [error-cases.env](./error-cases.env) - Error handling and edge cases

### Tree-sitter Queries
- [queries.scm](./queries.scm) - Example queries for finding specific patterns

## Quick Reference

### Supported Value Types
1. **Strings**: Double-quoted (with interpolation), single-quoted (literal)
2. **Booleans**: `true` and `false` (lowercase only)
3. **Numbers**: Integers (positive and negative)
4. **URIs**: URLs with schemes (http://, ftp://, etc.)
5. **Raw values**: Anything else

### Common Patterns
- Variable interpolation: `"Hello ${USER}"`
- Empty values: `KEY=`
- Comments: `# comment` or `; comment`
- Namespaces: `@scope:key=value`
- URL paths: `//host/:key=value`

## Usage Tips

1. **Test your configuration** with the parser:
   ```bash
   npx tree-sitter parse config.env
   ```

2. **Use queries** to find specific patterns in your configuration files

3. **Check error nodes** to identify syntax issues:
   ```bash
   npx tree-sitter parse --debug config.env
   ```