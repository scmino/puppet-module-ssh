# Install the packages necessary to run an SSH server.  Currently supports
# Debian and RHEL/CentOS.  Add other distributions as required.
#
class ssh::packages {
	ssh::noop { "ssh/packages/installed": }

	case $::operatingsystem {
		RedHat,CentOS: {
			$ssh_package = "openssh"
		}
		Debian: {
			$ssh_package = "openssh-server"
		}
		default: {
			fail("Unknown \$::operatingsystem; please improve ssh::packages")
		}
	}

	package { $ssh_package:
		before => Ssh::Noop["ssh/packages/installed"];
	}
}
