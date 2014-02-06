# Setup an SSH server, and set a few basic, common configuration parameters.
#
define ssh::server($protocol_version        = 2,
                   $permit_empty_passwords  = false,
                   $challenge_response_auth = false,
                   $syslog_facility         = AUTHPRIV,
                   $log_level               = INFO,
                   $password_auth           = true,
                   $forward_x11             = false,
                   $permit_root_login       = "without-password") {
	include ssh::packages

	ssh::noop {
		"ssh/server/installed":  require => Ssh::Noop["ssh/packages/installed"];
		"ssh/server/configured": require => Ssh::Noop["ssh/server/installed"];
	}

	case $::operatingsystem {
		RedHat,CentOS: {
			$ssh_service   = "sshd"
			$ssh_hasstatus = true
			$ssh_restart   = "/sbin/service sshd reload"
		}
		Debian,Ubuntu: {
			$ssh_service   = "ssh"
			$ssh_hasstatus = true
			$ssh_restart   = "/usr/sbin/service ssh reload"
		}
		default: {
			fail("Unknown \$::operatingsystem; please improve ssh::server")
		}
	}

	ssh::sshd_config {
		"Protocol":                        value => $protocol_version;
		"PermitEmptyPasswords":
			value => $permit_empty_passwords ? {
				true  => yes,
				false => no,
			};
		"ChallengeResponseAuthentication":
			value => $challenge_response_auth ? {
				true  => yes,
				false => no,
			};
		"SyslogFacility":                  value => $syslog_facility;
		"LogLevel":                        value => $log_level;
		"PasswordAuthentication":
			value => $password_auth ? {
				true  => yes,
				false => no,
			};
		"X11Forwarding":
			value => $forward_x11 ? {
				true  => yes,
				false => no,
			};
		"PermitRootLogin":
			value => $permit_root_login ? {
				true               => yes,
				false              => no,
				"without-password" => "without-password",
			};
	}

	service { $ssh_service:
		ensure    => running,
		enable    => true,
		hasstatus => $ssh_hasstatus,
		restart   => $ssh_restart,
		subscribe => Ssh::Noop["ssh/server/configured"];
	}
}
