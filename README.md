# Zsh npm Global Recorder

This plugin keeps a reproducible list of globally installed npm packages by observing your shell. Whenever you run `npm install -g <package>` the package name is appended to `~/.default-npm-packages` (or a custom file), and `npm uninstall -g <package>` removes it. The result pairs well with tools like `mise` or any dotfiles workflow that relies on `~/.default-npm-packages`.

## Features

- Detects successful `npm install -g` commands and appends package names without duplicates.
- Detects `npm uninstall -g` and removes matching entries.
- Normalizes versions/tags (e.g., `foo@1.2.3`, `@scope/foo@beta`) to bare package names.
- Preserves symlink targets when updating the package list file.
- Respects `DEFAULT_NPM_PKGS_FILE` and `MISE_NODE_DEFAULT_PACKAGES_FILE` if set.

## Installation

Add the plugin through your preferred Zsh plugin manager. Common examples:

**zinit**

```zsh
zplug "yanskun/zsh-npm-global-recorder"
```

**Sheldon**

```zsh
[plugins.zsh-npm-global-recorder]
github = "yanskun/zsh-npm-global-recorder"
```

## Verification

```zsh
npm install -g npm-check-updates
npm uninstall -g npm-check-updates
```

By default the plugin writes to `~/.default-npm-packages`. If the file is a symlink, only its contents are updated; the link itself remains intact. Set `DEFAULT_NPM_PKGS_FILE` or `MISE_NODE_DEFAULT_PACKAGES_FILE` to override the location.
