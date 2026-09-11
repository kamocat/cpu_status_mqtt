#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP;

# Get device name from /etc/hostname
my $hostname = '';
if (open my $fh, '<', '/etc/hostname') {
    $hostname = <$fh>;
    chomp $hostname;
    close $fh;
}
$hostname ||= 'unknown';

# Device configuration (auto-derived from hostname)
my $device_id = lc($hostname) . '_server';
my $device_name = ucfirst($hostname) . ' Server';
my $state_topic = "homeassistant/server/$hostname/status";

# Define sensors with their configuration
my @sensors = (
    {
        id => 'temperature',
        name => 'CPU Temperature',
        unit => '°C',
        device_class => 'temperature',
        field => 'temperature',
    },
    {
        id => 'frequency',
        name => 'CPU Frequency',
        unit => 'MHz',
        device_class => 'frequency',
        field => 'frequency',
    },
    {
        id => 'cpu_user',
        name => 'CPU User',
        unit => '%',
        field => 'cpu_user',
    },
    {
        id => 'cpu_sys',
        name => 'CPU System',
        unit => '%',
        field => 'cpu_sys',
    },
    {
        id => 'mem_use',
        name => 'Memory Used',
        unit => 'MB',
        field => 'mem_use',
    },
    {
        id => 'mem_free',
        name => 'Memory Free',
        unit => 'MB',
        field => 'mem_free',
    },
    {
        id => 'swap_use',
        name => 'Swap Used',
        unit => 'MB',
        field => 'swap_use',
    },
    {
        id => 'disk_available',
        name => 'Disk Available',
        unit => 'MB',
        field => 'disk_available',
    },
    {
        id => 'disk_use_percent',
        name => 'Disk Usage',
        unit => '%',
        field => 'disk_use_percent',
    },
);

# Build discovery object
my %discovery = (
    qos => 1,
    dev => {
        mdl => 'Linux Server',
        sw => 'Perl CPU Status Monitor',
        ids => $device_id,
        name => $device_name,
        mf => 'Custom',
    },
    o => {
        name => 'CPU Status Monitor',
        sw => '1.0.0',
    },
    cmps => {},
);

# Generate sensor configurations
foreach my $sensor (@sensors) {
    my $unique_id = "${device_id}_$sensor->{id}";
    my $cmps = {
        unit_of_measurement => $sensor->{unit},
        value_template => "{{value_json.$sensor->{field}}}",
        name => $sensor->{name},
        expire_after => 600,
        p => 'sensor',
        unique_id => $unique_id,
        state_topic => $state_topic,
    };
    
    # Add device_class if specified
    if ($sensor->{device_class}) {
        $cmps->{device_class} = $sensor->{device_class};
    }
    
    $discovery{cmps}{$unique_id} = $cmps;
}

# Write to file
open my $fh, '>', 'discovery.json' or die "Cannot open discovery.json: $!";
print $fh JSON::PP->new->canonical->pretty->encode(\%discovery);
close $fh;

print "Generated discovery.json successfully\n";

# Load MQTT credentials from environment file (simple KEY=VALUE format)
my $env_file = 'mqtt.env';
if (-f $env_file) {
    open my $fh, '<', $env_file or die "Cannot open $env_file: $!";
    while (<$fh>) {
        chomp;
        next if /^#/ || /^\s*$/;
        my ($key, $val) = split /=/, $_, 2;
        $ENV{$key} = $val if defined $key && defined $val;
    }
    close $fh;
}
# Publish to MQTT using mosquitto_pub
my $mqtt_addr = $ENV{MQTT_ADDR} || 'localhost';
my $mqtt_user = $ENV{MQTT_USER} || '';
my $mqtt_pass = $ENV{MQTT_PASS} || '';

my $topic = "homeassistant/device/$hostname/config";

my @cmd = ('mosquitto_pub', '-h', $mqtt_addr, '-t', $topic, '-f', 'discovery.json');
push @cmd, '-u', $mqtt_user, '-P', $mqtt_pass if $mqtt_user && $mqtt_pass;

system(@cmd);

print "Published discovery to MQTT broker at topic: $topic\n";
