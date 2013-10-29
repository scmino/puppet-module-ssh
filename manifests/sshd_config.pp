# Set an sshd_config configuration parameter.
#
# For most configuration parameters, which only accept a single value, you
# can only use $key (aka $name) and $value.  The few which take multiple
# values must be instead manipulated via $add and $remove.
#
define ssh::sshd_config($key    = $name,
                        $value  = undef,
                        $add    = undef,
                        $remove = undef) {
	case $key {
		AllowAgentForwarding,AllowTcpForwarding,ChallengeResponseAuthentication,
		GSSAPIAuthentication,GSSAPIKeyExchange,GSSAPICleanupCredentials,
		GSSAPIStrictAcceptorCheck,GSSAPIStoreCredentialsOnRekey,
		HostbasedAuthentication,HostbasedUsesNameFromPacketOnly,IgnoreRhosts,
		IgnoreUserKnownHosts,KerberosAuthentication,KerberosGetAFSToken,
		KerberosOrLocalPasswd,KerberosTicketCleanup,KerberosUseKuserok,
		PasswordAuthentication,PermitEmptyPasswords,PermitUserEnvironment,
		PrintLastLog,PrintMotd,PubkeyAuthentication,RhostsRSAAuthentication,
		RSAAuthentication,ShowPatchLevel,StrictModes,TCPKeepAlive,UseDNS,UseLogin,
		UsePAM,UsePrivilegeSeparation,X11Forwarding,X11UseLocalhost: {
			$multivalued = false
			if $value and $value !~ /^(yes|no)$/ {
				fail("Invalid value for ${key}: ${value}")
			}
		}
		AddressFamily: {
			$multivalued = false
			if $value and $value !~ /^(inet6?|any)$/ {
				fail("Invalid value for ${key}: ${value}")
			}
		}
		Compression: {
			$multivalued = false
			if $value and $value !~ /^(yes|no|delayed)$/ {
				fail("Invalid value for ${key}: ${value}")
			}
		}
		GatewayPorts: {
			$multivalued = false
			if $value and $value !~ /^(yes|no|clientspecified)$/ {
				fail("Invalid value for ${key}: ${value}")
			}
		}
		PermitRootLogin: {
			$multivalued = false
			if $value and $value !~ /^(yes|no|without-password|forced-commands-only)$/ {
				fail("Invalid value for ${key}: ${value}")
			}
		}
		PermitTunnel: {
			$multivalued = false
			if $value and $value !~ /^(yes|no|point-to-point|ethernet)$/ {
				fail("Invalid value for ${key}: ${value}")
			}
		}
		ClientAliveCountMax,ClientAliveInterval,KeyRegenerationInterval,
		LoginGraceTime,MaxAuthTries,MaxSessions,MaxStartups,Port,
		ServerKeyBits,X11DisplayOffset: {
			$multivalued = false
			if $value and $value !~ /^\d+$/ {
				fail("Invalid value for ${key}: ${value}")
			}
		}
		LogLevel: {
			$multivalued = false
			if $value and $value !~ /^(QUIET|FATAL|ERROR|INFO|VERBOSE|DEBUG[123]?)$/ {
				fail("Invalid value for ${key}: ${value}")
			}
		}
		SyslogFacility: {
			$multivalued = false
			if $value and $value !~ /^(DAEMON|USER|AUTH(PRIV)?|LOCAL[0-7])$/ {
				fail("Invalid value for ${key}: ${value}")
			}
		}
		Protocol: {
			$multivalued = false
			if $value and $value !~ /^\d+(,\d+)*$/ {
				fail("Invalid value for ${key}: ${value}")
			}
		}
		AcceptEnv: {
			$multivalued = true
			if $add and $add !~ /^[\w*?]+$/ {
				fail("Invalid value for ${key}: ${add}")
			}
			if $remove and $remove !~ /^[\w*?]+$/ {
				fail("Invalid value for ${key}: ${remove}")
			}
		}
		/^(Allow|Deny)(Groups|Users)$/: {
			$multivalued = true
			if $add and $add !~ /^[\w.-]+$/ {
				fail("Invalid value for ${key}: ${add}")
			}
			if $remove and $remove !~ /^[\w.-]+$/ {
				fail("Invalid value for ${key}: ${remove}")
			}
		}
		AuthorizedKeysFile,AuthorizedPrincipalsFile,Banner,Ciphers,ForceCommand,
		HostCertificate,HostKey,ListenAddress,PermitOpen,PidFile,RevokedKeys,
		AuthorizedKeysCommand,AuthorizedKeysCommandRunAs,TrustedUserCAKeys,
		XAuthLocation: {
			# FIXME: Validation
			$multivalued = false
		}
		default: {
			fail("${key} can not be managed by ssh::sshd_config")
		}
	}

	Augeas {
		incl    => "/etc/ssh/sshd_config",
		lens    => "Sshd.lns",
		require => Noop["ssh/server/installed"],
		notify  => Noop["ssh/server/configured"],
	}

	if $value {
		if $multivalued {
			fail("${key} is a multivalued key; you must use add or remove")
		}

		augeas { "ssh/config/${key}":
			changes => "set ${key} '${value}'",
			onlyif  => "match ${key}[.='${value}'] size == 0";
		}
	} else {
		if $add or $remove {
			if ! $multivalued {
				fail("${key} is not a multivalued key; you must not use add or remove")
			}

			if $add {
				augeas { "ssh/config/${key}/${add}":
					changes => "set ${key}[last()+1]/1 '${add}'",
					onlyif  => "match ${key}[*]/*[.='${add}'] size == 0";
				}
			}
			if $remove {
				case $key {
					AcceptEnv: {
						exec {
							"remove ${remove} from ${key}":
								command => "sed -ri \"s/^(AcceptEnv\s)(.*\s)?(${remove}\s?)/\1\2/g\" /etc/ssh/sshd_config",
								onlyif  => "grep 'AcceptEnv' /etc/ssh/sshd_config | grep \"${remove}\"",
								notify  => Exec["${key}-${remove}-cleanup"];
							"remove empty ${key} after ${remove}":
								alias       => "${key}-${remove}-cleanup",
								command     => 'sed -ri "/^AcceptEnv\s?$/d" /etc/ssh/sshd_config',
								refreshonly => true;
						}
					}
					default: {
						fail("This doesn't work. Hack up the above to work as required, or do it right with augeas.")
					}
				}
			}
		} else {
			augeas { "ssh/config/${key}":
				changes => "rm ${key}",
				onlyif  => "match ${key} size > 0";
			}
		}
	}
}
