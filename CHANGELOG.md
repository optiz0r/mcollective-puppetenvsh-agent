Changelog
=========

0.6
---

 - Add an mcollective application for use as 'mco pupetenvsh' without needing
   to interact with the rpc interface directly.
 - Update the README with an r10k comparison

0.5
---

 - Add support for local_environments
 - Update packaging documentation for RedHat/CentOS/Debian

0.4
---

 - Remove --recurse-submodules option from git fetch which isn't supported
   on RHEL6.

0.3
---

 - Puppetfile.lock should be tested for existance not for being a directory.
   This was overzealous search/replace introduced in 0.2.

0.2
---

 - Updates for compatibility on RHEL 6/ruby 1.8.7
 - Improved documentation

0.1
---

 - Initial version
