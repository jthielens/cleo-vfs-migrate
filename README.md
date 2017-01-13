# README #

The `cleo-migrate.pl` tool aids in the migration and management of the
Cleo Harmony VFS configuration file `vfs.yaml` in a manner similar to
the approach Connect:Enterprise uses to manage mailboxes.

In Connect:Enterprise, each mailbox `id` has its configuration defined
in an associated `id.RSD` file.  The view of the FTP or SFTP home
directory for the mailbox then appears with a folder named `id`, which
maps to the `id` subdirectory of the system mailbox root.

Connect:Enterprise also allows additional mailboxes to be made visible
through the `MAILBOX_LIST` parameter in the RSD file.  For each
additional mailbox in the `MAILBOX_LIST`, an additional folder named
for the mailbox appears in the FTP/SFTP root and maps to the appropriate
physical folder under the mailbox root.

In Cleo Harmony VFS, the users are defined in the core Harmony UI/API
and are stored in "OmniHost" user groups, ultimately represented in
XML files.  The VFS configuration is organized into templates, each of
which defines a set of mappings for FTP/SFTP home folder "paths" to
various destinations, including simple physical folder mappings.

## VFS Model ##

The `cleo-migrate.pl` utility implements a Connect:Enterprise emulation
model in `vfs.yaml` as follows:

* The mailbox root is represented as a parent `File` configuration
  in the `properties` section.  This piece of configuration is not
  managed by the utility, but must be entered in the `vfs.yaml` file
  beforehand.  Both `type: File` and `name: mailbox` are required,
  but `autocreate:` may be set as needed.

```
properties:
- name: mailbox
  type: File
  properties:
    basepath: /file/server/root
    autocreate: true or false as needed
```

* For each mailbox `id`, a template named for the `id` is created.
  The template includes a mapping for the `id` plus any associated
  mailboxes as follows:

```
templates:
  id:
  - path: id
    type: File
    parent: mailbox
    properties:
      subpath: id
  - path: mailbox-A
    type: File
    parent: mailbox
    properties:
      subpath: mailbox-A
...
```

* The mapping for the id-and-mailbox-list configuration is represented on the command
  line and bulk import file in a comma-separated single-line format.  For example,
  the configuration for mailbox `id` with additional visibility into mailboxes
  `mailbox-A` and `mailbox-B` would be represented as follows:
  
```
id,mailbox-A,mailbox-B
```

## Command Line ##

```
usage: cleo-migrate.pl: [options] [file...]

options: -add    id,mbx,... add a new mailbox mapping for id
         -delete id,mdx,... delete the mailbox mapping for id
         -list   id,...     list the mailbox mapping for ids
         -in     file,...   read CSV file for batch -add
         -home   path       Cleo home directory (defaults to .)
         -out    file       write updated YAML to file (instead of in place)
         -err    file       rediect STDERR
         -help              display this message and exit
         -q                 suppress notes and errors (like 2>/dev/null)
         -v                 display version history and exit
         -V                 display version number and exit

Note that -add and -delete may appear multiple times, once for each mapping
to be added or delete in the form id,mailbox,mailbox.

-list may appear multuple times or multiple ids may appear in a single
argument in the form id,id,id (not id,mailbox,mailbox).

By default the vfs.yaml file is updated in place and the existing file is
moved into a backup.  Use -out to specify an alternate output file for
testing, which leaves the vfs.yaml unchanged.  Use -out - to output to
STDOUT.
```

## Installation ##

The utility is a stand-alone perl script with no additional module dependencies.
Install from GitHub as follows:

```
sudo wget -nv -q -O /usr/local/bin/cleo-migrate.pl "https://raw.githubusercontent.com/jthielens/cleo-vfs-migrate/master/cleo-migrate.pl"
sudo chmod a+x /usr/local/bin/cleo-migrate.pl
cleo-migrate.pl -help
```

If `sudo` access is not available, the utility can be downloaded to any writable
location and invoked as `./cleo-migrate.pl`.