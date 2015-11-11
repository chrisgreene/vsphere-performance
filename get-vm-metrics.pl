#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use VMware::VIRuntime;
use Time::HiRes;

my $perfmgr_view;       # View to PerfManager Object
my $entity;             # View to entity
my $all_counters;       # pointer to structure that maintains the counters
my %counter_by_name;    # tracks <group>.<name>.<summary> for each counter

my %opts = (
   vm => {
      type => "=s",
      help => "Name of entity to query",
   },
   file => {
      type => "=s",
      help => "Name of file to hold output",
   },
   countertype => {
      type => "=s",
      help => "Counter type [cpu | mem | net | disk | sys]",
      default => '.',
   },
   instance => {
      type => "=s",
      help => "Name of instance to query",
      default => '',
   },
   interval => {
      type => "=i",
      help => "Interval in seconds",
      default => 20,
   },
   samples => {
      type => "=i",
      help => "Number of samples to retrieve",
      default => 1,
   },
);


my $time_start = format_time(Time::HiRes::gettimeofday());

# read/validate options and connect to the server
Opts::add_options(%opts);
Opts::parse();
Opts::validate();
Util::connect();

$perfmgr_view = Vim::get_view(mo_ref => Vim::get_service_content()->perfManager);
my $perfCounterInfo = $perfmgr_view->perfCounter;

my $interval = Opts::get_option('interval');
my $samples  = Opts::get_option('samples');

my ($start, $end);
if ($interval == 20) {
   # real-time stats: leave start and end undefined, set number of samples
} 

init_perf_counter_info();

my $entitytype = 'VirtualMachine';
my $vm = Opts::get_option('vm');

if (Opts::option_is_set('vm')) {
   $entity = Vim::find_entity_view(view_type => $entitytype,
                                   filter    => {'name' => $vm});
   if (!defined($entity)) {
      die "Entity $vm not found.\n";
   }
} 

my $avail_metric_ids = ($perfmgr_view->QueryAvailablePerfMetric(entity => $entity));
my $metric_ids_count = @$avail_metric_ids;

$interval = 20;
$samples  = 180;

my @counter_names;# = qw(mem.active.average mem.granted.average);
my @test_metrics;

if (@counter_names) {
  foreach my $counter_name (@counter_names) {
    my $counter = $counter_by_name{$counter_name};
    push @test_metrics, PerfMetricId->new (counterId => $counter->key, instance => '')
  }
}
else {
  @test_metrics = @$avail_metric_ids;
}

# build new available metrics to only contain items wehre the instance only equals ''
my $perf_query_spec = PerfQuerySpec->new(
                         entity     => $entity,
                         metricId   => \@test_metrics,
                         intervalId => $interval,
                         maxSample  => $samples,
                         format     => 'normal');

my $perf_data = $perfmgr_view->QueryPerf(querySpec => $perf_query_spec);

my @timestamps = $perf_data->[0]->sampleInfo;

foreach my $results (@{$perf_data->[0]->value}) {
  my $output = '';
  my $instance_uuid = $entity->summary->config->instanceUuid;
  open(my $outputFile, '>>', "/tmp/$instance_uuid.txt") or die "Could not open /tmp/$instance_uuid.txt $!";

  for (my $i = 0; $i < $#{$results->value}; ++$i) {
    my $timestamp     = format_timestamp($timestamps[0]->[$i]->{'timestamp'});
    my $power_state   = $entity->runtime->powerState->val;
    my $metric_value  = ${$results->value}[$i],
    my $metric_name   = join (".", $all_counters->{$results->id->counterId}->groupInfo->key, 
                                   $all_counters->{$results->id->counterId}->nameInfo->key, 
                                   $all_counters->{$results->id->counterId}->rollupType->val);
    my $unit_info = $all_counters->{$results->id->counterId}->unitInfo->label;
    $output .= sprintf "%s,%s,%s,%s,%s,%s,%s\n", $vm, $instance_uuid, $power_state, $metric_name, $timestamp, $metric_value, $unit_info;
  } 
  print $outputFile $output;
  close $outputFile;
}

my $time_end = format_time(Time::HiRes::gettimeofday());

print "Start: $time_start - End: $time_end\n";

sub init_perf_counter_info {
   $perfmgr_view = Vim::get_view(mo_ref => Vim::get_service_content()->perfManager);
   my $perfCounterInfo = $perfmgr_view->perfCounter;
   foreach (@$perfCounterInfo) {
      my $key = $_->key;
      $all_counters->{$key} = $_;
      my $name = join (".", $_->groupInfo->key, $_->nameInfo->key, $_->rollupType->val);
      #print "Duplicate counter $name \n" if (exists $counter_by_name{$name});
      $counter_by_name{$name} = $_;
   }
}

sub format_timestamp {
  # transform "2015-06-09T19:52:20Z" to "6/8/2015 4:27:40 PM"

  my $timestamp = $_[0];
  my ($date, $time) = split('T', $timestamp);
  
  my ($year, $month, $day) = ( $date =~ /(\d{4})-(\d{2})-(\d{2})/g );
  $time = (split('Z', $time))[0];
  my ($hour, $minute, $second) = split(':', $time);
  
  my $ampm = 'AM';
  if ($hour > 12) { 
    $hour -= 12; 
    $ampm = 'PM';
  }
 
  my $formatted_date = sprintf("%d/%d/%d %d:%s:%s %s", $month, $day, $year, $hour, $minute, $second, $ampm);
  return $formatted_date;
}

sub format_time {
   my ($arg) = @_;
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($arg);
   my $hrs = $hour + ($yday * 24);
   ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime ($arg);
   my $tz = ($hour + ($yday * 24)) - $hrs;
   $year = $year + 1900;
   $mon = $mon + 1;
   my $string = sprintf("%.4d-%.2d-%.2dT%.2d:%.2d:%.2d%.2d:00", $year, $mon, $mday, $hour, $min, $sec, $tz);
   return $string;
}
