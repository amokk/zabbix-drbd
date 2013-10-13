#!/usr/bin/perl

# install libjson-perl library or edit drbd_discovery()

# possible items:
#   'protocol' => 'C',
#   'ua' => '0',
#   'ro_local' => 'Primary',
#   'ds_local' => 'UpToDate',
#   'ep' => '1',
#   'lo' => '0',
#   'ds_remote' => 'UpToDate',
#   'id' => '0',
#   'bm' => '0',
#   'nr' => '0',
#   'ro_remote' => 'Primary',
#   'oos' => '0',
#   'flags' => 'r-----',
#   'dw' => '0',
#   'dr' => '332',
#   'al' => '0',
#   'ns' => '0',
#   'cs' => 'Connected',
#   'wo' => 'f',
#   'pe' => '0',
#   'ap' => '0'
#   'name' => 'r0'
#
#   'version' => '8.4.3 (api:1/proto:86-101)'


use strict;
use warnings;
use File::stat;
use Data::Dumper;
use JSON;
use Switch;

# config
my $procdrbd = "/proc/drbd";
my $cachefile = ".drbd";
my $tmpdir = "/tmp/zabbix-drbd";
my $cacheexpire = 60; # seconds

# runtime
my %drbd;
my %resources;
my %resource;

mkdir $tmpdir;

sub get_data {
    my $file = "$tmpdir/$cachefile";
    my $data;
    if ( ! -e $file) {
        write_cache_file($file, $data = read_proc());
        return $data;
    }
    # wtf why $mtimestamp = (stat($file))[9]; is not working ???
    my $filestat = stat($file) || die "$!";
    my $mtimestamp = (defined(@$filestat[9]) ? @$filestat[9] : 0);
    if ((time - $mtimestamp) > $cacheexpire) {
        $data = read_proc();
        write_cache_file($file, $data);
        return $data;
    }
    return eval { do $file };
}

# caching is because we don't want to read /proc/drbd for every item
# cache file can be placed into tmpfs for better performance
sub write_cache_file {
    my ($file,$data) = @_;
    open(FILE, ">$file") || die "Can not open: $!";
    print FILE Data::Dumper->Dump([$data],["data"]);
    close(FILE) || die "Error closing file: $!";
}

sub get_res_names {
    # TODO use perl
    my $devresdir = "/dev/drbd/by-res";
    my @data = `ls -l $devresdir` if ( -e $devresdir);
    foreach(@data) {
        chomp;
        if (my($resname, $resid) = m/.*\s(\w+)\s->.*drbd(\d+)$/) {
            $drbd{'resources'}{$resid}{'name'} = $resname;
        }
    }
}

sub read_proc {
    my ($resid);
    open DRBD, $procdrbd || die "$!";

    while (<DRBD>) {
        chomp;
        # version: 8.3.13 (api:88/proto:86-96)
        if (m/^version/) {
            ($drbd{'version'}) = /^version: (.*)/;
            next;
        }

        # 0: cs:Connected ro:Primary/Primary ds:UpToDate/UpToDate C r-----
        # 0: cs:StandAlone ro:Primary/Unknown ds:UpToDate/DUnknown   r-----
        if (m/^[ ]+[0-9]+:/) {
            %resource = ();
            @resource{'id', 'cs', 'ro_local', 'ro_remote', 'ds_local', 'ds_remote', 'protocol', 'flags'} = 
                /\s+(\d+):\s+cs:(\w+)\s+ro:(\w+)\/(\w+)\s+ds:(\w+)\/(\w+)\s(.)\s+(\S+).*/;
            
            $resid = $resource{'id'};
            # wtf ... find solution for next 2 lines
            my %tmphash = %resource;
            $resources{$resid} = \%tmphash;
        }

        # ns:1 nr:2 dw:3 dr:880336 al:5 bm:6 lo:7 pe:8 ua:9 ap:10 ep:11 wo:b oos:13
        if (m/^\s+ns:/) {
            @resource{'ns', 'nr', 'dw', 'dr', 'al', 'bm', 'lo', 'pe', 'ua', 'ap', 'ep', 'wo', 'oos'} = 
                /^\s+ns:(\d+)\s+nr:(\d+)\s+dw:(\d+)\s+dr:(\d+)\s+al:(\d+)\s+bm:(\d+)\s+lo:(\d+)\s+pe:(\d+)\s+ua:(\d+)\s+ap:(\d+)\s+ep:(\d+)\s+wo:(\w)\s+oos:(\d+).*/;
            # wtf ... find solution for next 2 lines
            my %tmphash = %resource;
            $resources{$resid} = \%tmphash;
            $resid = "";
       }
    }
    $drbd{'resources'} = \%resources;
    get_res_names();
    return \%drbd;
}

sub drbd_discovery {
    my $data = get_data();
    my @out;                                                                                                                                                                                                                                 
     
    for my $k1 ( sort keys %{$data->{'resources'}} ) {
        push(@out, {
           '{#DRBDRESID}' => $data->{'resources'}->{$k1}->{'id'},
           '{#DRBDRESNAME}' => $data->{'resources'}->{$k1}->{'name'},
        });
    }
    print encode_json({'data'=>\@out});
}

sub drbd_item {
    my ($resid, $item) = @_;
    my $data = get_data();
    print $data->{'resources'}->{$resid}->{$item} if (defined($data->{'resources'}->{$resid}->{$item}));
}

sub drbd_version {
    my $data = get_data();
    print $data->{'version'};
}

switch($ARGV[0]) {
    case "discovery" { drbd_discovery(); }
    case "item" { drbd_item($ARGV[1], $ARGV[2]); }
    case "version" { drbd_version(); }
}
