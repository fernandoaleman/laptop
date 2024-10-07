# MySQL 5.7

`mysql-client@5.7` is now expired in homebrew, so we will need to install it manually.

Tap homebrew-core

```
brew tap homebrew/core --force
```

Edit the `mysql-client@5.7` formula

```
brew edit mysql-client@5.7
```

Remove the line that begins with

```
disable! date:
```

Install `mysql-client@5.7`

```
HOMEBREW_NO_INSTALL_FROM_API=1 brew install mysql-client@5.7
```

Link mysql binaries

```
brew link --force mysql-client@5.7
```
