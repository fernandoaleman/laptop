Laptop
======

Laptop is a script to set up a Mac OS X laptop for Rails development.

Requirements
------------

### Mac OS X

Install a C compiler:

For Snow Leopard (10.6): use [OS X GCC
Installer](https://github.com/kennethreitz/osx-gcc-installer/).

For Lion (10.7) or Mountain Lion (10.8): use [Command Line Tools for
XCode](https://developer.apple.com/downloads/index.action).

For Mavericks (10.9): installed with the script, no prerequisite.

Install
-------

### Mac OS X

Read, then run the script:

    bash <(curl -s https://raw.githubusercontent.com/fernandoaleman/laptop/master/mac) | tee ~/laptop.log

Debugging
---------

Your last Laptop run will be saved to `~/laptop.log`. Read through it to see if
you can debug the issue yourself. If not, copy the lines where the script
failed into a [new GitHub
Issue](https://github.clickhere.com/clickherelabs/laptop/issues/new) for us. Or, attach the
whole log file as an attachment.

What it sets up
---------------

* Zsh as your shell
* Bundler gem for managing Ruby libraries
* Exuberant Ctags for indexing files for vim tab completion
* Hub gem for interacting with the GitHub API
* Homebrew for managing operating system libraries (OS X only)
* ImageMagick for cropping and resizing images
* Node.js and NPM, for running apps and installing JavaScript packages
* Postgres for storing relational data
* Rails gem for writing web applications
* Rbenv for managing versions of the Ruby programming language
* Redis for storing key-value data
* Ruby Build for installing Rubies
* Ruby stable for writing general-purpose code
* The Silver Searcher for finding things in files
* Tmux for saving project state and switching between projects

It should take less than 15 minutes to install (depends on your machine).

Laptop can be run multiple times on the same machine safely. It will upgrade
already installed packages and install and activate a new version of ruby (if
one is available).

Make your own customizations
----------------------------

Put your customizations in `~/.laptop.local`. For example, your
`~/.laptop.local` might look like this:

    #!/bin/sh

    brew tap caskroom/cask
    brew install brew-cask

    brew cask install dropbox
    brew cask install google-chrome
    brew cask install rdio

You should write your customizations such that they can be run safely more than
once. See the `mac` script for examples.

Contributing
------------

Please see [CONTRIBUTING.md](https://github.clickhere.com/clickherelabs/laptop/blob/master/CONTRIBUTING.md).
