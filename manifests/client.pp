# client.pp - configure a munin node
# Copyright (C) 2007 David Schmitt <david@schmitt.edv-bus.at>
# See LICENSE for the full license granted to you.

class munin::client {

	$munin_port_real = $munin_port ? { '' => 4949, default => $munin_port } 
	$munin_host_real = $munin_host ? {
		'' => $fqdn, 
		'fqdn' => $fqdn, 
		default => $munin_host
	}

	case $operatingsystem {
		darwin: { include munin::client::darwin }
		debian: {
			include munin::client::debian
			include munin::plugins::debian
		}
		ubuntu: {
			info ( "Trying to configure Ubuntu's munin with Debian class" )
			include munin::client::debian
			include munin::plugins::debian
		}
		default: { fail ("Don't know how to handle munin on $operatingsystem") }
	}

	case $kernel {
		linux: {
			case $vserver {
				guest: { include munin::plugins::vserver }
				default: {
					include munin::plugins::linux
					case $virtual {
						xen0: { include munin::plugins::xen }
					}
				}
			}
		}
		default: {
			err( "Don't know which munin plugins to install for $kernel" )
		}
	}

}

define munin::register()
{
	@@file { "munin_node_${name}": path => "${NODESDIR}/$name",
		ensure => present,
		content => template("munin/defaultclient.erb"),
	}
}

define munin::register_snmp()
{
	@@file { "munin_snmp_${name}": path => "${NODESDIR}/$name",
		ensure => present,
		content => template("munin/snmpclient.erb"),
	}
}

class munin::client::darwin 
{
	file { "/usr/share/snmp/snmpd.conf": 
		mode => 744,
		content => template("munin/darwin_snmpd.conf.erb"),
		group  => staff,
		owner  => root,
	}
	delete_matching_line{"startsnmpdno":
		file => "/etc/hostconfig",
		pattern => "SNMPSERVER=-NO-",
	}
	append_if_no_such_line{"startsnmpdyes":
		file => "/etc/hostconfig",
		line => "SNMPSERVER=-YES-",
		notify => Exec["/sbin/SystemStarter start SNMP"],
	}
	exec{"/sbin/SystemStarter start SNMP":
		noop => false,
	} 
	munin::register_snmp { $fqdn: }
}

class munin::client::debian 
{
	err("munin port: $munin_port_real" )
	err("munin host: $munin_host_real" )

	package { "munin-node": ensure => installed }

	file {
		"/etc/munin/munin-node.conf":
			content => template("munin/munin-node.conf.${operatingsystem}.${lsbdistcodename}"),
			mode => 0644, owner => root, group => root,
			require => Package["munin-node"],
			notify => Service["munin-node"],
	}

	service { "munin-node":
		ensure => running, 
		hasstatus => true,
	}

	munin::register { $munin_host_real: }

	# workaround bug in munin_node_configure
	plugin { "postfix_mailvolume": ensure => absent }
}
