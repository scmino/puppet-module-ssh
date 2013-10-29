A very simple, understated SSH management module.  Why yet another one? 
Because this one [doesn't
suck](http://www.hezmatt.org/~mpalmer/blog/2013/10/29/why-your-puppet-module-sucks.html).


# Managing SSH keys

## Adding keys

Very simple:

    ssh::authorized_key { "Some unique comment":
       user => "fred",
       type => "ssh-dss",
       key  => "AAAAB3NzaC1kc3MAAACBANTE47Dy..."
    }

What you're basically saying here is "please add this key to the `fred`
user's `authorized_keys` file".  You can also specify "options" for the SSH
key, which are the things at the beginning of the key that tell SSH to
restrict the use of the key in some way, like this:

    ssh::authorized_key { "Restrictive key":
       user    => "fred",
       type    => "ssh-dss",
       key     => "AAAAB3NzaC1kc3MAAACBANTE47Dy...",
       options => ["no-X11-forwarding",
                   "no-pty",
                   "from=\"192.0.2.0/24\"",
                   "command=\"/bin/echo Fred's not home, man\""
                  ]
    }

The value for `options` must be an array containing the options you wish to
set for the key, one option per array item.  Note the need to escape the
(mandatory) quotes in options that take a value (`from` and `command` in the
above example).  See `sshd`(8) for details of what valid options are for
your version of SSH.


## Removing keys

If you want a specific key to be definitely removed from an
`authorized_keys` file, you can `ensure => absent`, like so:

    ssh::authorized_key { "Bob isn't allowed to login as fred":
       ensure => absent,
       user   => "fred",
       type   => "ssh-dss",
       key    => "AAAAB3NzaC1kc3MAAACBANTE47Dy..."
    }

This will ensure that no key of the specified type and content appears in
the user's `authorized_keys`.


## Ensuring only "known" keys are kept

It would be terribly embarrassing to discover that an attacker managed to
break into your systems, and then kept their access by dropping an SSH key
into a user's `authorized_keys` and you never realised it.  More
prosaically, it's a royal pain to have to enumerate every key that's ever
been removed from a user's `authorized_keys`, just in case some machine
hasn't run Puppet in a while.

For all these reasons and more, you can do this:

    ssh::authorized_key { "Known keys only for fred, please":
       ensure => specified_only,
       user   => "fred"
    }

This will discard any key from `fred`'s `authorized_keys` that doesn't have
an `ssh::authorized_key` defined somewhere in the node manifest.  Tres cool,
when it works; just be careful of those occasional situations where you
*want* to have a manually-configured key somewhere...


# Installing an SSH server

To simplify the installation and configuration of an SSH server, you can
simply use the `ssh::server` type, like so:

    ssh::server { "ssh": }

This will install and enable an SSH server on the default port, and tweak a
few settings to improve security (it'll make sure that
`PermitEmptyPasswords` is `no`, for instance).

You can tweak a couple of commonly-used configuration parameters with
options to this type:

* `protocol_version`: (default: `"2"`)  Which SSH protocol version(s) to
  support.  The default is in line with modern OpenSSH defaults, but if you
  have a hankering for some old-school SSH v1, you can set this to `"1,2"`.

* `password_auth`: (default: `true`)  If you want to be extra-secure, you can
  set this to `false` to only permit login using keys.

* `forward_x11`: (default: `false`)  X11 forwarding has a bit of a history of
  security "gotchas", so we turn it off by default.  If you need to run
  remote X11 apps, then you can set this to `true` to enable it system-wide.

* `permit_root_login`: (default: `"without-password"`)  Letting people SSH
  into your machine as `root` with only a password for protection is...
  unwise, if your machine is open to the Internet.  As a result, we default
  this setting to `"without-password"`.  You can change it to any of the
  other valid values for the `PermitRootLogin` configuration option (`yes`,
  `no`, or `forced-commands-only`) if you need to.


## Custom configuration

Pretty much any `sshd_config` setting may be managed from Puppet by using
the `ssh::sshd_config` type.  For the vast majority of options, you'll want
to use this simple form:

    ssh::sshd_config { "UsePAM": value => "no" }

The configuration option you want to set should be the namevar, and the
value of the variable is specified by the `value` parameter.

There are a couple of config variables that are "multi-valued", and are
defined as a list.  For those, you need to use something more like this:

    ssh::sshd_config { "gimme my TERM":
       key => "AcceptEnv",
       add => "TERM"
    }

Or perhaps like this:

    ssh::sshd_config { "Never let LD_PRELOAD get passed in":
       key    => "AcceptEnv",
       remove => "LD_PRELOAD"
    }

Basically, you're stating that a given value must *always* be present in the
list of values, or else it can *never* appear in the list of values.
