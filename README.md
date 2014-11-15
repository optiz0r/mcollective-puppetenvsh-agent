mcollective-puppetenvsh-agent
=============================

An mcollective agent to manage dynamic puppet environments and modules
mastered in git.

It uses the git and librarian-puppet binaries via shell calls to 
minimise the number of Ruby libraries required. This is useful when deploying
to older distributions such as RHEL6.

Prerequisites
-------------

 - It assumes the user mcollective is running under has access to a
   passwordless SSH key suitable for accessing your git repositories
 - It requires a copy of your git repository be checked out into
   $environmentpath/.puppet.git.

Installation
------------

 - Gentoo - An ebuild is available in my sihnon overlay:
   https://github.com/optiz0r/gentoo-overlay
 - Sabayon - Pre-built packages are available in my packages.sihnon.net
   entropy overlay: http://pkg.sihnon.net/entropy/standard/packages.sihnon.net/
 - RedHat/Centos/Debian - Agent can be packaged using `mco plugin package`.

For other platforms, install the plugin manually by copying the agent and util
directories into your mcollective plugin directory. Or feel free to build a
native package and submit a PR with build steps.

Configuration
-------------

The following configuration parameters are available:

 - `basedir` - Base directory which contains dynamic environments and the
    master repo. Defaults to `/etc/puppet/environments`.
 - `master_repo_name` - Name of the directory under basedir which contains the
    master repo. Defaults to `.puppet.git`.
 - `upstream` - Name of the git remote to pull changes from when updating.
    Defaults to `origin`.
 - `local_environments` - A comma-separated list of local environment directories
    that won't be managed by the agent. Suitable for containing development
    environments on test puppetmasters. Not intended to be used on production
    masters. Defaults to "live".
 - `use_librarian` - Whether to use librarian-puppet to manage modules.
    Defaults to `false`.
 - `git` - Path to git binary to use. Defaults to `git`, using whatever's
    in `$PATH`.
 - `new_workdir` - Path to git-new-workdir binary to use. Defaults to
   `git-new-workdir`, using whatever's in `$PATH`.
 - `librarian` - Path to librarian-puppet binary to use. Defaults to
   `librarian-puppet`, using whatever's in `$PATH`.

Special configuration for running under RHEL/CentOS 6
 - `use_ruby193` - Whether to use ruby193 to run the librarian. Defaults to
   `false`.
 - `ruby193_env` - Path to the environment file to be sourced when enabling
   ruby193. Defaults to `/opt/rh/ruby193/enable`, which is the script provided
   by the SCL build.

Usage
-----

The following actions are supported:

 - Return a list of all the dynamic environments currently available on the
   master
```
mco puppetenvsh list [$filters]
```
 - Checkout a new dynamic environment from the git branch named `foo`
```
mco puppetenvsh add foo [$filters]
```
 - Update the dynamic environment to the latest commit in git branch named `foo`
```
mco puppetenvsh update foo [$filters]
```
 - Delete the dynamic environment named `foo`
```
mco puppetenvsh rm foo [$filters]
```
 - Update all dynamic environments from git. Any missing environments will be
   created, existing ones updated, and any stale environments no longer present
   in git will be removed.
```
mco puppetenvsh update-all [$filters]
```

Similar projects
----------------

This project fulfils similar requirements as r10k
(https://github.com/adrienthebo/r10k). The principal differences are:
 - It supports modules stored in git submodules
 - It uses librarian-puppet to manage modules. librarian-puppet supports
   automatic dependency resolution for forge modules
 - As an mcollective plugin, orchestration is built-in. This is most
   useful when you have a fleet of puppet masters that all need to be
   updated simultaneously.

Contributions
-------------

Contributions are welcome! please feel free to submit a pull request.

Licence
-------

This project is made available under the MIT license.
