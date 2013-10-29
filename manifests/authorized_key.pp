# Wrapper for the native _ssh_authorized_key type into something nice and
# namespaced.
#
define ssh::authorized_key($ensure = present,
                           $user,
                           $options = [],
                           $type,
                           $key)
	authorized_key { $name:
		ensure  => $ensure,
		user    => $user,
		options => $options,
		type    => $type,
		key     => $key;
	}
}
