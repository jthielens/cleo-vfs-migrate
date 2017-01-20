#!/usr/bin/perl

use strict;

my $VERSION = <<"";
Version Description                        Date   Who
------- ---------------------------------- ------ ---
1.0.0   original version                   170113 jbt

my $V = (split (' ', (split ("\n", $VERSION, 4))[2], 2))[0];

#==============================================================================#
#                                  u s a g e                                   #
#==============================================================================#

(my $PROGRAM = $0) =~ s/.*[\/\\]//;
my $USAGE=<<".";

usage: $PROGRAM: [options] [file...]

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
.

my $opt;

#==============================================================================#
#                                o p t i o n s                                 #
#==============================================================================#

my $DEBUG = 0;

sub Getopts
    #--------------------------------------------------------------------------#
    # usage: my $opt = Getopts('a:bc@{flag}', \@error);                        #
    #                                                                          #
    # Argument describes options as a sequence of option definitions.  Each    #
    # definition consists of an option letter or a brace-enclosed option word  #
    # followed by an optional mode character.  The mode may be : for a single- #
    # value option ($opt_* is set to the value), @ for a multi-valued option   #
    # (values are pushed onto @opt_*), or missing for a boolean option ($opt_* #
    # is set to 1 if the option appears).                                      #
    #                                                                          #
    # An option may also be followed by [suboption,...], in which case the     #
    # option must be invoked as -option[suboption,...] (no spaces!) or         #
    # -option.  In this case, $opt_* is set if any suboption is chosen, and    #
    # $opt_*{*} is set for each suboption specified.  -option by itself        #
    # selects all suboptions.                                                  #
    #                                                                          #
    # Returns 1 if no errors were encountered.  Error disgnostics are pushed   #
    # onto @$error each error encountered.                                     #
    #--------------------------------------------------------------------------#
{
    my $argumentative = shift @_;
    my $error         = shift @_;
    my %args;
    my $arg;
    my $mode;
    my $first;
    my $rest;
    my $errs = 0;
    my $opt = {};

    while ($argumentative) {
        $argumentative =~ /\s*(\w|\{\w+\})([:@]|\[[^\]]*\])?(.*)/;
        ($arg,$mode,$argumentative) = ($1,$2,$3);
        $arg =~ s/[{}]//g;
        if ($mode =~ /^\[/) {
            for my $suboption (split (',', substr ($mode, 1, length ($mode)-2))) {
                $args{"$arg.$suboption"} = $suboption;
                print "args{$arg.$suboption} = $suboption\n" if $DEBUG;
            }
            $mode = '[';
        }
        $args{$arg} = $mode ? $mode : '';
    }

    while(@ARGV && ($_ = $ARGV[0]) =~ /^-(.)(.*)/) {
        ($first,$rest) = ($1,$2);
        my $t = "$first$rest";
        #--------------------------------#
        # look for -option[suboptions,,, #
        #--------------------------------#
        if ($t =~ /(\w+)(\[.*)/ && $args{$1} eq '[') {
            $first = $1;
            $rest  = $2;
        } elsif(defined $args{$t}) {
            ($first,$rest) = ($t,'');
        }
        if(defined $args{$first}) {
            if($args{$first} eq '[') {
                #-------------------------------------#
                # $first is an option with suboptions #
                #-------------------------------------#
                shift(@ARGV);
                $opt->{$first} = 1;
                print "\$opt_$first = 1;\n" if $DEBUG;
                if($rest =~ /^\[/) {
                    #--------------------------------------#
                    # we had -option[suboptions,...]stuff: #
                    #    put "stuff" back on ARGV          #
                    #--------------------------------------#
                    if($rest =~ /^(\[[^\]]*\])(.+)/) {
                        $rest = $1;
                        unshift(@ARGV, "-$2");
                    }
                } elsif($rest eq '' && @ARGV && $ARGV[0] =~ /^\[.*\]$/) {
                    #----------------------------------------------#
                    # we had -option <whitespace> [suboptions,...] #
                    #----------------------------------------------#
                    $rest = shift(@ARGV);
                }
                if ($rest) {
                    #---------------------------------#
                    # we had some explicit suboptions #
                    #---------------------------------#
                    $rest =~ s/^\[//;
                    $rest =~ s/\]$//;
                    for my $suboption (split (',', $rest)) {
                        next unless $suboption;
                        my @hits = grep (/^$first.$suboption/, keys %args);
                        if (@hits) {
                            for my $hit (grep (/^$first.$suboption/, keys %args)) {
                                $opt->{$first} = {} unless defined $opt->{$first};
                                $opt->{$first}->{$args{$hit}} = 1;
                                print "\$opt_$first\{$args{$hit}\} = 1;\n" if $DEBUG;
                            }
                        } else {
                            ++$errs;
                            push @$error, "unknown suboption: $first\[$suboption\]";
                        }
                    }
                } else {
                    #--------------------------------------#
                    # no explicit suboptions: set them all #
                    #--------------------------------------#
                    $opt->{$first} = {} unless defined $opt->{$first};
                    for my $suboption (grep (/^$first\./, keys %args)) {
                        $opt->{$first}->{$args{$suboption}} = 1;
                        print "\$opt_$first\{$args{$suboption}\} = 1;\n" if $DEBUG;
                    }
                }
            } elsif($args{$first}) {
                #------------------------------------------------------#
                # $first is a single- or multi- valued option (: or @) #
                #------------------------------------------------------#
                shift(@ARGV);
                if($rest eq '') {
                    if (@ARGV) {
                        $rest = shift(@ARGV);
                    } else {
                        ++$errs;
                        push @$error, "option requires a value: $first";
                    }
                }
                if ($args{$first} eq '@') {
                    $opt->{$first} = [] unless defined $opt->{$first};
                    push @{$opt->{$first}}, $rest; # split (',', $rest);
                    print "push (\@opt_$first, $rest);\n" if $DEBUG;
                } else {
                    $opt->{$first} = $rest;
                    print "\$opt_$first = $rest;\n" if $DEBUG;
                }
            } else {
                #----------------------------#
                # $first is a simple Boolean #
                #----------------------------#
                $opt->{$first} = 1;
                print "\$opt_$first = 1;\n" if $DEBUG;
                if($rest eq '') {
                    shift(@ARGV);
                } else {
                    $ARGV[0] = "-$rest";
                }
            }
        } else {
            push @$error, "unknown option: $first";
            ++$errs;
            if($rest ne '') {
                $ARGV[0] = "-$rest";
            } else {
                shift(@ARGV);
            }
        }
    }
    return $errs ? undef : $opt;
}

#==============================================================================#
#                                   y a m l                                    #
#==============================================================================#

sub load_yaml
    #--------------------------------------------------------------------------#
    # usage: $yaml = load_yaml \@error;                                        #
    #--------------------------------------------------------------------------#
{
    my $error = shift;

    my $fn = ($opt->{home} || '.') . "/conf/vfs.yaml";
    my $chunk = {type=>'prefix', lines=>[]};
    my $yaml = {chunks=>[$chunk]};
    my @indents = (0);
    my $looking_for_templates = 0;

    if (open (my $fh, '<', $fn)) {
        while (chomp(my $line = <$fh>)) {
            if ($line =~ /\S/) {
                # --- calculate logical column ---
                $line =~ /[-\s]*/;
                my $spaces = $+[0];
                pop @indents while $spaces < $indents[-1];
                if ($spaces > $indents[-1]) {
                    push @indents, $spaces;
                }
                my $column = $#indents;
                # --- check for chunk shift ---
                if ($looking_for_templates && $column==1) {
                    (my $name = $line) =~ s/\s*(.*):/\1/;
                    $chunk = {type=>'template',
                              name=>$name,
                              mounts=>[],
                              lines=>[]};
                    push @{$yaml->{chunks}}, $chunk;
                } elsif ($looking_for_templates && $column==0) {
                    $chunk = {type=>'suffix', lines=>[]};
                    push @{$yaml->{chunks}}, $chunk;
                    $looking_for_templates = 0;
                } elsif ($chunk->{type} eq 'prefix' && $line eq 'templates:') {
                    $looking_for_templates = 1;
                }
                # --- process template details ---
                if ($chunk->{type} eq 'template') {
                    if ($column==2 && $line =~ /^\s*-/) {
                        push @{$chunk->{mounts}}, {};
                    }
                    if ($column>=2) {
                        $line =~ /[-\s]*([^:]*):\s*(.*?)\s*$/;
                        ${$chunk->{mounts}}[-1]->{$1} = $2;
                    }
                }
            }
            push @{$chunk->{lines}}, $line;
        }
        # --- stuff suffix aside for the moment ---
        if ($chunk->{type} eq 'suffix') {
            $yaml->{suffix} = pop @{$yaml->{chunks}};
        }
        close $fh;
    } else {
        push @$error, "Can't open YAML file $fn: $!";
        return undef;
    }
    return $yaml;
}

sub print_yaml
    #--------------------------------------------------------------------------#
    # usage: if (!defined print_yaml($yaml, $fn, \@error)) {...}               #
    #--------------------------------------------------------------------------#
{
    my $yaml = shift;
    my $fn = shift;
    my $error = shift;

    my $fh;
    if ($fn eq '-') {
        open ($fh, '>&STDOUT');
    } elsif (!open ($fh, '>', $fn)) {
        push @$error, "Can't open YAML file for output $fn: $!";
        return undef;
    }
    if ($#{$yaml->{chunks}} > 0 &&
        $yaml->{chunks}->[0]->{type} eq 'prefix' &&
        defined $yaml->{chunks}->[0]->{lines} &&
        $yaml->{chunks}->[0]->{lines}->[-1] ne 'templates:') {
        # the prefix does not end in templates:, but now there are some
        push @{$yaml->{chunks}->[0]->{lines}}, 'templates:';
    }
    for my $chunk (@{$yaml->{chunks}}, $yaml->{suffix}) {
        for my $line (@{$chunk->{lines}}) {
            print $fh $line, "\n";
        }
    }
    close $fh unless $fn eq '-';
    return 1;
}

#==============================================================================#
#                                  i n p u t                                   #
#==============================================================================#

sub parse_add
    #--------------------------------------------------------------------------#
    # usage: $mailbox = parse_add $line;                                       #
    #                                                                          #
    # Parses a csv line into a master mailbox and its links:                   #
    #    { mailbox => 'mailbox',                                               #
    #      list    => ['A', 'B', ...] }                                        #
    #--------------------------------------------------------------------------#
{
    my $line = shift;

    my @columns = split /\s*,\s*/, $line;
    my $mailbox = shift @columns;
    return {mailbox => $mailbox, list => \@columns}
}

sub csv_input
    #--------------------------------------------------------------------------#
    # usage: $mailboxes = cmd_input (\@input, \@error, \@note);                #
    #                                                                          #
    # Read input files from @input.  Push errors and notes onto @error/@note.  #
    # Returns an ARRAYREF of HASHREFs, one for each mailbox, as follows:       #
    #    { mailbox => 'mailbox',                                               #
    #      list    => ['A', 'B', ...] }                                        #
    #--------------------------------------------------------------------------#
{
    my $input = shift @_;
    my $error = shift @_;
    my $note  = shift @_;

    my $result = [];
    unshift (@$input, '-') unless @$input;
    for my $in (@$input) {
        if (open(my $fh, '<', $in)) {
            while (my $line = <$fh>) {
                $line =~ s/[\r\n]+$//;
                push @$result, parse_add($line);
            }
            close $fh;
        } else {
            push @$error, "Can't open $in: $!";
        }
    }
    return $result;
}

sub format_mailbox
    #--------------------------------------------------------------------------#
    # usage: $mailbox = format_mailbox $descriptor;                            #
    #                                                                          #
    # Formats a YAML chunk:                                                    #
    #    { type => 'template',                                                 #
    #      name => $name,                                                      #
    #      lines => [                                                          #
    #          '  $name:',                                                     #
    #      ... for each $mailbox, A, C, ...                                    #
    #          '  - path: $mailbox',                                           #
    #          '    type: File',                                               #
    #          '    parent: mailbox',                                          #
    #          '    properties:',                                              #
    #          '      subpath: $mailbox',                                      #
    # From a mailbox descriptor:                                               #
    #    { mailbox => 'mailbox',                                               #
    #      list    => ['A', 'B', ...] }                                        #
    #--------------------------------------------------------------------------#
{
    my $descriptor = shift;

    my $mailbox = {type => 'template',
                   name => $descriptor->{mailbox}};
    my @lines = ("  $descriptor->{mailbox}:");
    my @mounts = [];
    for my $id ($descriptor->{mailbox}, @{$descriptor->{list}}) {
        push @lines, "  - path: $id",
                     "    type: File",
                     "    parent: mailbox",
                     "    properties:",
                     "      subpath: $id";
        push @mounts, { path => $id,
                        type => 'File',
                        parent => 'mailbox',
                        subpath => $id };
    }
    $mailbox->{lines} = \@lines;
    $mailbox->{mounts} = \@mounts;
    return $mailbox;
}

sub audit_mailbox
    #--------------------------------------------------------------------------#
    # usage: $string = audit_mailbox $mailbox;                                 #
    #                                                                          #
    # Formats an audit string from a YAML chunk:                               #
    #    { type => 'template',                                                 #
    #      name => $name,                                                      #
    #      lines => [                                                          #
    #          '  $name:',                                                     #
    #      ... for each $mailbox, A, C, ...                                    #
    #          '  - path: $mailbox',                                           #
    #          '    type: File',                                               #
    #          '    parent: mailbox',                                          #
    #          '    properties:',                                              #
    #          '      subpath: $mailbox',                                      #
    #      mounts => [                                                         #
    #      ... for each $mailbox, A, C, ...                                    #
    #          { path => $id,                                                  #
    #            subpath => $id, or                                            #
    #            basepath => /prefix/path/$id                                  #
    #--------------------------------------------------------------------------#
{
    my $mailbox = shift;

    my $audit = $mailbox->{name};
    for my $mount (@{$mailbox->{mounts}}) {
        $audit .= ",$mount->{path}" unless $mount->{path} eq $mailbox->{name};
    }
    return $audit;
}

#==============================================================================#
#                                   m a i n                                    #
#==============================================================================#

my @error;
my @note;
my @info;

my $yaml;
my $adds;

my $updates = 0;

#-----------------------------#
# Command line and easy outs. #
#-----------------------------#
my $SPEC = '{in}@{home}:{add}@{delete}@{list}@{out}:{err}:Vv{help}q';
if (!defined ($opt=Getopts ($SPEC, \@error)) || $opt->{help}) {
    push @info, $USAGE;
}

push @info, $V       if $opt->{V};
push @info, $VERSION if $opt->{v};

#-----------#
# Load YAML #
#-----------#
if (!(@error or @info)) {
    $yaml = load_yaml \@error;
}

#-----------#
# Read adds #
#-----------#
if (!(@error or @info)) {
    if (defined $opt->{add}) {
        my @adds = map {parse_add $_} @{$opt->{add}};
        $adds = \@adds;
    }
    if (defined $opt->{in}) {
        unshift @ARGV, @{$opt->{in}};
    }
    if (@ARGV) {
        my $csv = csv_input \@ARGV, \@error, \@note;
        if (defined $csv) {
            $adds = [] unless defined $adds;
            push @$adds, @$csv;
        }
    }
}


#--------------------#
# Process Operations #
#--------------------#
if (!(@error or @info)) {
    if (defined $adds) {
        my %index = map {$yaml->{chunks}->[$_]->{name} => $_}
                        (0..$#{$yaml->{chunks}});
        for my $add (@$adds) {
            my $id = $add->{mailbox};
            if (defined $index{$id}) {
                push @info, "replacing mailbox $id";
                $yaml->{chunks}->[$index{$id}] = format_mailbox($add);
            } else {
                push @info, "adding  mailbox $id";
                push @{$yaml->{chunks}}, format_mailbox($add);
                $index{$id} = $#{$yaml->{chunks}};
            }
            $updates++;
        }
    }
    if (defined $opt->{delete}) {
        my %deletes = map {($_ =~ s/,.*$//r) => 0} @{$opt->{delete}};
        # go backwards so we don't have to rework indices
        for my $i (reverse(0..$#{$yaml->{chunks}})) {
            my $name = $yaml->{chunks}->[$i]->{name};
            if (defined $deletes{$name}) {
                $deletes{$name} = 1;
                push @info, "deleting mailbox $name at position $i\n";
                splice @{$yaml->{chunks}}, $i, 1;
                $updates++;
            }
        }
        for my $test (keys %deletes) {
            push @info, "mailbox $test not found, not deleted"
                unless $deletes{$test};
        }
    }
    if (defined $opt->{list}) {
        my %index = map {$yaml->{chunks}->[$_]->{name} => $_}
                        (0..$#{$yaml->{chunks}});
        for my $ids (@{$opt->{list}}) {
            for my $id (split /,/, $ids) {
                if (defined $index{$id}) {
                    push @info, audit_mailbox($yaml->{chunks}->[$index{$id}]);
                } else {
                    push @info, "mailbox $id not found, not listed";
                }
            }
        }
    }
}

#--------------#
# Print output #
#--------------#
if (!@error) {
    if (!$updates) {
        push @info, "no records updated"
            if defined $adds or defined $opt->{delete};
    } else {
        if (!$opt->{out}) {
            $opt->{out} = ($opt->{home} || '.') . "/conf/vfs.yaml";
        }
        if ($opt->{out} ne '-' && -e $opt->{out}) {
            my $mtime = (stat($opt->{out}))[9];
            my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($mtime);
            my $bak =  sprintf ".%04d%02d%02d-%02d%02d%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec;
            push @info, "$opt->{out} exists: renaming to $opt->{out}$bak";
            rename $opt->{out}, "$opt->{out}$bak";
        }
        print_yaml $yaml, $opt->{out}, \@error;
        push @info, $updates." record".($updates==1?'':'s')." updated";
    }
}

#-------------------#
# Print diagnostics #
#-------------------#
if (!$opt->{q} and (@error or @note or @info)) {
    if (!($opt->{err} and open (ERR, ">$opt->{err}"))) {
        open (ERR, ">&STDERR");
    }

    print ERR 'note: '. join ("\nnote: ",  @note)."\n"  if @note;
    print ERR 'error: '.join ("\nerror: ", @error)."\n" if @error;
    print ERR           join ("\n",        @info)."\n"  if @info;
    close (ERR);
}
