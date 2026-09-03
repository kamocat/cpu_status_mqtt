#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP;

# Load MQTT credentials from environment file
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

# Load state_topic from discovery.json
my $topic = get_topic_from_discovery();

my %data;

# Get temperature (millidegrees to celsius)
$data{temperature} = get_temperature();

# Get CPU frequency (kHz to MHz)
$data{frequency} = get_frequency();

# Get memory stats (kB)
my %mem = get_memory();
@data{keys %mem} = values %mem;

# Get CPU stats (user and sys only)
my %cpu = get_cpu_stats();
@data{keys %cpu} = values %cpu;

# Get disk stats
my %disk = get_disk_stats();
@data{keys %disk} = values %disk;

# Generate JSON
my $json = JSON::PP->new->canonical->encode(\%data);

# Publish to MQTT using mosquitto_pub
my $mqtt_addr = $ENV{MQTT_ADDR} || 'localhost';
my $mqtt_user = $ENV{MQTT_USER} || '';
my $mqtt_pass = $ENV{MQTT_PASS} || '';

# Write JSON to temp file and publish
my $temp_file = '/tmp/mqtt_status.json';
open my $fh, '>', $temp_file or die "Cannot write temp file: $!";
print $fh $json;
close $fh;

my @cmd = ('mosquitto_pub', '-h', $mqtt_addr, '-t', $topic, '-f', $temp_file);
push @cmd, '-u', $mqtt_user, '-P', $mqtt_pass if $mqtt_user && $mqtt_pass;

system(@cmd);
unlink $temp_file;

sub get_topic_from_discovery {
    my $discovery_file = 'discovery.json';
    die "discovery.json not found. Run generate_discovery.pl first.\n" unless -f $discovery_file;
    
    open my $fh, '<', $discovery_file or die "Cannot open discovery.json: $!";
    my $discovery = JSON::PP->new->decode(do { local $/; <$fh> });
    close $fh;
    
    # Get state_topic from first sensor in cmps
    if (my $cmps = $discovery->{cmps}) {
        for my $sensor_id (keys %$cmps) {
            return $cmps->{$sensor_id}{state_topic} if $cmps->{$sensor_id}{state_topic};
        }
    }
    
    die "No state_topic found in discovery.json\n";
}

sub get_temperature {
    my @temps;
    opendir my $dh, '/sys/class/thermal' or die "Cannot open thermal: $!";
    while (my $zone = readdir $dh) {
        next unless $zone =~ /^thermal_zone\d+$/;
        my $temp_file = "/sys/class/thermal/$zone/temp";
        if (open my $fh, '<', $temp_file) {
            my $temp = <$fh>;
            chomp $temp;
            close $fh;
            push @temps, $temp / 1000;  # Convert millidegrees to celsius
        }
    }
    closedir $dh;
    
    if (@temps) {
        my $sum = 0;
        foreach my $t (@temps) {
            $sum += $t;
        }
        return $sum / @temps;  # Average
    }
    return undef;
}

sub get_frequency {
    my $freq_file = '/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq';
    return unless -f $freq_file;
    
    open my $fh, '<', $freq_file or return;
    my $freq = <$fh>;
    chomp $freq;
    close $fh;
    
    return ($freq / 1000) + 0;  # Convert kHz to MHz
}

sub get_memory {
    my $output = `free -L`;
    
    my %memory;
    # Parse line with SwapUse, CachUse, MemUse, MemFree
    foreach my $line (split /\n/, $output) {
        my @fields = split /\s+/, $line;
        # Look for line starting with "SwapUse"
        if (@fields >= 8 && $fields[0] eq 'SwapUse') {
            $memory{swap_use} = $fields[1] + 0;
            # fields[2] = 'CachUse'
            $memory{cache_use} = $fields[3] + 0;
            # fields[4] = 'MemUse'
            $memory{mem_use} = $fields[5] + 0;
            # fields[6] = 'MemFree'
            $memory{mem_free} = $fields[7] + 0;
            last;
        }
    }
    
    return %memory;
}

sub get_cpu_stats {
    my $output = `mpstat 1 1`;
    
    my %cpu;
    # Look for the Average line with CPU stats
    foreach my $line (split /\n/, $output) {
        my @fields = split /\s+/, $line;
        if (@fields >= 4 && $fields[0] eq 'Average:' && $fields[1] eq 'all') {
            # Fields: Average, all, %usr, %nice, %sys, ...
            # Index:  0,       1,    2,    3,      4
            $cpu{cpu_user} = $fields[2] + 0;  # %usr
            $cpu{cpu_sys} = $fields[4] + 0;   # %sys
            last;
        }
    }
    
    return %cpu;
}

sub get_disk_stats {
    my $output = `df -text4 --output=avail,pcent`;
    
    my %disk;
    # Skip header, parse data line
    my @lines = split /\n/, $output;
    if (@lines > 1) {
        my $data_line = $lines[1];
        my @fields = split /\s+/, $data_line;
        if (@fields >= 2) {
            # First field is available (may include unit like 171G), second is use%
            my $avail = $fields[0];
            my $percent = $fields[1];
            # Remove % if present
            $percent =~ s/%$//;
            $disk{disk_available} = $avail + 0;
            $disk{disk_use_percent} = $percent + 0;
        }
    }
    
    return %disk;
}
