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

The VFS works in conjunction with the OmniHost user configuration.  It is important that any user for whom a template is created using this tool also have a mailbox defined.  The recommended Home Directory configuration is:

```
vfs:/templates=%username%/%username%
```

This means that all users must have a template defined for them, including users who only have access to their own mailbox.  For this reason, after adding a user mapping, the resulting configuration is cross-referenced and any users added in the mailbox list for a user who do not also have an existing mailbox will have a default configuration implicitly added.  For example, after

```
cleo-migrate.pl -add user1,user2,user3
```

The configuration for `user1` is added (or updated) to include references to the mailboxes for `user2` and `user3` in addition to the default mapping for `user1` itself.  If configurations for `user2` and `user3` are not found in `vfs.yaml`, then templates will be automatically defined for them as if the following command had been issued:

```
cleo-migrate.pl -add user1,user2,user3 -add user2 -add user3
```

Any user template managed with `cleo-migrate.pl` must conform to the conventions understood by the tool.  In particular, any user mailboxes that are shared (like `user2` and `user3` in the above example) must be conforming.  An attempt to add a non conforming template will result in an error and the `vfs.yaml` will have to be adjusted manually (or the noncomforming template can be deleted with `-delete`).  This restriction arises from the need to control the mapping between the paths and the underlying storage consistently.  But `vfs.yaml` may be used for other purposes outside of these conventions, so this restriction avoids unintentional misconfiguration.

## Command Line ##

```
usage: cleo-migrate.pl: [options] [file...]

options: -add    id,mbx,... add a new mailbox mapping for id
         -delete id,mdx,... delete the mailbox mapping for id
         -list   id,...     list the mailbox mapping for ids
         -all               list all the mailbox mappings
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
argument in the form id,id,id (not id,mailbox,mailbox).  To list all mailboxes
use -all.

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

## Extended Example ##

### Initial Setup ###

To get started with this example:

* Create an "OmniHost" user host in Harmony.  Use the recommended settings on the General tab for folders, but you may choose whatever privileges are required on the Privileges tab.

```
General tab:
    Home Directory: vfs:/templates=%username%/%username%
    User Download Folder: ./
    User Upload Folder: ./
Privileges tab:
	Protocols: [*] FTP
	           [*] SSH FTP
	           [*] HTTP
	Access: ( ) Read access
	        ( ) File access
	        (*) Full access
```

* Designate and create a file system location for the mailboxes. This example uses `/mailbox/harmony/user` on a local drive, but any path can be used and a shared file system mount point is typically used in production.

```
$ sudo mkdir /mailbox/harmony/user
$ sudo chown cleo:cleo /mailbox/harmony/user
```

* Create an initial `vfs.yaml` file in the Harmony `conf` directory.  The conventions of the tool require that a File properties block named _mailbox_ be defined with a `basepath` directed to the selected file system location.

```
properties:
- name: mailbox
  type: File
  properties:
    basepath: /mailbox/harmony/user
    autocreate: true
```

### Add a User ###

With this configuration, two steps are required to enable a user for login:

* The user mailbox must be created in Harmony.  In the admin UI, select New User Mailbox on the Users host, and configure the user id and password.  It is also possible, but not required, to create additional User hosts, provided they follow the Folder conventions outlined above.  For this example, add the user `user1`.
* The folder mapping for the user is handled by the VFS through configuration in `conf/vfs.yaml`.  This step is handled by the `cleo-migrate.pl` tool.

```
$ cleo-migrate.pl -add user1
adding  mailbox user1
./conf/vfs.yaml exists: renaming to ./conf/vfs.yaml.yyyymmdd-hhmmss
1 record updated
```

This simple command format adds a basic VFS template for `user1` that gives the user access to their own mailbox in the `user1` folder.  Since the `vfs.yaml` properties include `autocreate: true`, the `/mailbox/harmony/user/user1` folder will automatically be created if it is not already present.

The contents of `vfs.yaml` at this point illustrate the path mapping conventions:

```
properties:
- name: mailbox
  type: File
  properties:
    basepath: /mailbox/harmony/user
    autocreate: true
templates:
  user1:
  - path: user1
    type: File
    parent: mailbox
    properties:
      subpath: user1
```

In the `user1` template, the `path` setting controls the folder name as perceived by the user (`user1`), and the `parent` and `subpath` settings define the physical storage location for the mailbox.

### Add a Shared Mailbox ###

Now extend the rights for `user1` to include access to the `user2` mailbox:

```
$ cleo-migrate.pl -add user1,user2
replacing mailbox user1
implicitly adding  mailbox user2
./conf/vfs.yaml exists: renaming to ./conf/vfs.yaml.yyyymmdd-hhmmss
2 records updated
```

In this syntax for `-add`, the first identifier is the primary mailbox being added (`user1`) and the subsequent identifiers are the additional mailboxes which should be shared with the primary (`user2`).  This is roughly equivalent to the Connect:Enterprise `MAILBOX_LIST`.  Note that since the `user1` template already exists, it's existing defintion is replaced with this command.  The resulting `vfs.yaml` is:

```
properties:
- name: mailbox
  type: File
  properties:
    basepath: /mailbox/harmony/user
    autocreate: true
templates:
  user1:
  - path: user1
    type: File
    parent: mailbox
    properties:
      subpath: user1
  - path: user2
    type: File
    parent: mailbox
    properties:
      subpath: user2
  user2:
  - path: user2
    type: File
    parent: mailbox
    properties:
      subpath: user2
```
Note that two separate additions have taken place:
* a `user2` subfolder has been added to the `user1` template, providing `user1` with access to the `user2` mailbox in addition to its own, and
* a basic `user2` template has been added as well.

This is the same outcome that would have resulted from:

```
$ cleo-migrate.pl -add user1,user2 -add user2
```

Note also that a backup copy of `vfs.yaml` has automatically been created.

### List Mailbox Definitions and Bulk Import ###

To audit the mailbox defintions, use `-all`:

```
$ cleo-migrate.pl -all
user1,user2
user2
```

The mailbox definitions are listed in the same format used in `-add`.  This output can be captured in a CSV file, which can later be used for bulk user import:

```
$ cleo-migrate.pl -all > users.csv
$ cat users.csv
user1,user2
user2
$ cleo-migrate.pl -in users.csv
replacing mailbox user1
replacing mailbox user2
./conf/vfs.yaml exists: renaming to ./conf/vfs.yaml.yyyymmdd-hhmmss
2 records updated
```

CSV files need not be generated from `-all`, but can be constructed independently in order to prepare bulk import files.

To list individual mailbox defintions use `-list`:

```
$ cleo-migrate.pl -list user1
user1,user2
```

### Delete a Mailbox ###

Delete a mailbox with `-delete`.

```
$ cleo-migrate.pl -delete user2
deleting mailbox user2
removing user2 from user1
./conf/vfs.yaml exists: renaming to test/conf/vfs.yaml.yyyymmdd-hhmmss
2 records updated
```

As with `-add`, the tool keeps the configuration in sync by not only deleting the template for `user2`, but also removing mappings of any other users that reference `user2`.

```
properties:
- name: mailbox
  type: File
  properties:
    basepath: /mailbox/harmony/user
    autocreate: true
templates:
  user1:
  - path: user1
    type: File
    parent: mailbox
    properties:
      subpath: user1
```

You can see that `user1` has been reduced to a simple mailbox as would have resulted from `-add user1`.

### Multiple Operations ###

A single invocation of `cleo-migrate.pl` may include multiple operations.  They are processed as follows:

* Individual additions from `-add mailbox,...` are processed.  `-add` may appear multiple times on the command line, once for each mailbox to add.
* Bulk additions from `-in filename` are processed.  Multiple files may be specified with multiple `-in filename` options and they are processed in order.
* Any referenced mailboxes not explictly added with `-add` or `-in` are processed.
* Individual deletions from `-delete mailbox` are processed.  `-delete` may appear multiple times.  Note that `-delete id1,id2` will only delete `id1`, as the `-add` and `-delete` arguments are handled consistently.
* If `-all` is requested, a mailbox audit list is produced on the standard output.
* If `-list id` options appear, the requested mailbox(es) are listed.  Note that unlike `-add` and `-delete`, multiple ids may be requested using the `-list id1,id2` syntax.

