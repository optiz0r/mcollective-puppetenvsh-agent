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
   passwordless SSH key suitable for accessing your git repository
 - It requires 'git-new-workdir' be available in your PATH
 - It requires a copy of your git repository be checked out into
   $environmentpath/.puppet.git.
