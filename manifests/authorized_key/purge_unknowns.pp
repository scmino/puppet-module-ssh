# Tell Puppet to purge keys from a user's authorized_keys file that aren't
# managed by Puppet.
#
# There are no parameters to pass to this type; simply specify the name of
# the user you'd like to purge keys for as the resource's namevar, like this:
#
#     ssh::authorized_key::purge_unknowns { "someuser": }
#
define ssh::authorized_key::purge_unknowns() {
	underscore_ssh_authorized_key { "purge_unknowns for $name":
		ensure => specified_only,
		user   => $name
	}
}
