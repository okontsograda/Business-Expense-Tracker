#!/usr/bin/perl

use warnings;
use strict;
use Getopt::Long;
use Data::Dumper;
use Term::ANSIColor qw(:constants);
use JSON;
use lib "/var/www/CaseSentry/lib/Perl";
use ConnectVars;
use Date::Parse;
use POSIX;
use Net::OpenSSH;

# Connect Vars
getConnectVars or die "Cannot retrieve values from ConnectVars\n";
my $MP_DB = $SAMPSON_DB;
my $DB_SERVER = $SAMPSON_DB_SERVER;
my $DB_USER = $SAMPSON_USER;
my $DB_PASSWORD = $SAMPSON_PASSWORD;


# SET GLOBAL VARIABLES
my $active;
my $help;
my $dbh;
my $cron_run;
my $debug;
my $hostname;
my $status;
my $notes;
my $group;
my $CONFIG;
my $site_type = '';
my $ndb_dbh;
my $hds_dbh;
my $clear_ccs;
my $system_type;
my $health_directory = "/home/sextant-support/sextant_healthchecks";
my $log_directory    = "/var/log/sextant_healthchecks/";
my $health_lockfile_directory = $health_directory . "/lockfiles";
my @group_status;
my @hosts;
my @running_processes;
my @health_checks_to_run;
my $CCS_trap_contents;
my $trap_host = '135.89.102.136';
my $trap_string = 'public';
my $CCS_notes;

# Values to check for if the option to run a certain group is passed
my %group_options = ( "system"      => 0,
                      "database"    => 0,
                      "application" => 0,
                      "processes"   => 0 );

# Values to check passed in arguements against
GetOptions (  "help"          => \$help,
              "hostname=s"    => \$hostname,
              "debug"         => \$debug,
              "cron-run"      => \$cron_run,
              "group=s"       => \$group,
              "send-clear"    => \$clear_ccs );

#----------------------------------- START OPTIONS LOGIC -----------------------------------
if ( $hostname eq 'all' && !$cron_run ) {
  print "\n-> All to be used only with cron-run\n";
  &print_usage;
  } elsif ( $help || !$hostname || $hostname eq '' ) {
  # If $help is passed OR $hostname value is not passed -> Print Usage
  if ( $help ) {
    &print_usage;
  } else {
    print "\n-> hostname must be initialized and not empty\n";
    &print_usage;
  }
} elsif ( $clear_ccs ) {
  if ( $group ) {
    my $lock_file = $health_lockfile_directory . "/healthwarn_" . $hostname . "_" . $group . ".lock";
    my $send = 'false';

    # Check if the lock file exists for the alarm we want to clear
    if ( -e $lock_file ) {
      # If the lock file exists, let's remove it since we passed
      if ( unlink ( $lock_file ) ) {
        log_message ( "[$hostname][$group] $lock_file removed successfully", 5 );
        # Since we found the lockfile, set the flag to true so the sendclear can be sent
        $send = 'true';
      } else {
        log_message ( "[$hostname][$group][error] Unable to remove $lock_file", 5 );
      }
    } else {
      print "Lock file not found - Checking for hostname configuration file\n-> $lock_file\n";
      log_message ( "[$hostname][$group] Lock file not found - Checking for hostname configuration file", 1 );

      # If the lockfile was not found, check for a config file to determine server exists
      if ( -e $health_directory . '/config/CFG_$hostname.json' ) {
        log_message ( "[$hostname][$group] $hostname configuration found - Sending Clear", 1 );
        $send = 'true';
      } else {
        print "Lockfile and server configuration not found - Unable to send clear message\n-> $health_directory/config/CFG_$hostname.json\n";
        log_message ( "[$hostname][$group] Lockfile and server configuration not found - Unable to send clear message", 1 );
      }
    }
    print $send . "\n";
    if ( $send eq 'true' ) {
      $CCS_trap_contents .= "================ " . uc ( $group ) . " ================\nManual clear sent for $group";

      #Send Clear message to CCS
      `(/bin/echo "\nNode: Health:$hostname:$group:clear"; /bin/echo -e "$CCS_trap_contents") | /var/www/CaseSentry/bin/sendTrapCS.pl $trap_host $trap_string`;

      log_message ( "[$hostname][$group] Returning Manual Clear", 5 );
      log_message ( "[$hostname][$group] Detail: Node: Health:$hostname:$group:clear", 5 );
      log_message ( "[$hostname][$group] Lock file removed -> $lock_file\n$CCS_trap_contents", 5 );
      exit (0);
    } else {
      log_message ( "[$hostname][$group] Unable to send clear - Lock file or Host config not found", 5 );
      exit(0);
    }
  } else {
    print "Please specify group to send clear message for\n";
    exit (0);
  }
} elsif ( $cron_run ) {
  if ( $hostname eq "all" ) {
    $group = "all";
  } else {
    print "\n-> cron run should only be run with hostname=all\n";
    &print_usage;
  }
} elsif ( $group ) {
  if ( !exists $group_options { $group } ) {
    print "\n-> Unknown test group: $group\n\n";
    &print_usage;
  } elsif ( $cron_run ) {
    print "\n-> Cannot use group arg with cron instance\n\n";
    &print_usage;
  }
} else { $group = "all"; }

#----------------------------------- END OPTIONS LOGIC -------------------------------------


#----------------------------------- START SCRIPT LOGIC ------------------------------------

# Check to see if /home/sextant-support is ia working directory. If not, create it.
if ( ! ( -d '/home/sextant-support/' ) ) {
  print "Logging directory not found...\nCreating /home/sextant-support/...\n";
  mkdir ( '/home/sextant-support' ) or print "Unable to create /home/sextant-support/...\n";
}

if ( $debug ) {
  print "===================================\n\tDebug mode initiated\n\n";
  print "Hostname:\t$hostname\n";
  print "Group:\t\t$group\n" if $debug;
  print "===================================\n\n";
}

# Set global lockfile name for the host once the param is passed through from the user
my $lock_file = $health_directory . "/healthwarn_" . $hostname . "_" . $group . ".lock";

#--------- Check what instance of the healthchecks we need to run | Cron / Manual -------
if ( $group eq "all" ) {
  # If the cron option is passed, loop through the hostname array and execute the healthchecks for each host
  if ( $cron_run && $hostname eq "all" ) {
    # Load hosts to run healthchecks for
    my $HOST_CONFIG = &load_cron_config;
    my @enabled_hosts;

    # Parse the Hosts configuration to see which host is enabled and push to enabled_hosts array
    foreach my $host ( reverse sort keys $HOST_CONFIG->{ 'Hosts' } ) {
      my $check = $HOST_CONFIG->{ 'Hosts' }->{ $host };
      push ( @enabled_hosts, $host ) if $check eq "enabled";
    }

    foreach my $hostname ( @enabled_hosts ) {
      # Logging for testing purposes
      print "--- $hostname ---\n";

      # Load configuration file for health checks parameters
      $CONFIG = load_config( $hostname );

      # Connect to the correct database if the host requires it
      if ( $system_type =~ m/(CaseSentry|ETL)/o ) {
        # Establish the connection with the MySQL server
        $dbh = DBI->connect("DBI:mysql:$MP_DB:$hostname", "$DB_USER", "$DB_PASSWORD",{'PrintError' => 0}) or die log_message ( "Database connection not made: $DBI::errstr" );
      }

      # Check to see if the the host is an ETL
      if ( $system_type eq "ETL" ) {
        # Gather the site type ( Active or Passive )
        $site_type = get_site_type ( $dbh );
        if ( $site_type eq "Active" ) {
          # Get connections for the NDB and HDS
          $ndb_dbh = connect_to_cluster ( $dbh, 'SX_a1' );
          $hds_dbh = connect_to_hds ( $dbh );
        } elsif ( $site_type eq "Passive" ) {
          # CST 69571 -> Removed Passive Cluster connection. No reason to connect to passive cluster.
        }
      }

      # Get current running processes
      @running_processes = &sshCmd( $hostname, "/bin/ps auwx");

      # Gather health checks we need to run from the host configuration file
      @health_checks_to_run = keys $CONFIG->{ 'Health Checks' };

      # Debug Override - Force fping (system) check to fail
      # $hostname = '172.172.172.172' if $hostname eq "usa109st-etl1";

      # Execute the healthcheck groups
      &execute_healthchecks;
    }
  } else {
    # Load configuration file for health checks parameters
    $CONFIG = load_config( $hostname );

    # Connect to the correct database if the host requires it
    if ( $system_type =~ m/(CaseSentry|ETL)/o ) {
      # Establish the connection with the MySQL server
      $dbh = DBI->connect("DBI:mysql:$MP_DB:$hostname", "$DB_USER", "$DB_PASSWORD",{'PrintError' => 0}) or log_message( "[$hostname] Database connection not made: $DBI::errstr", 3, "[dbh handle]");
    }

    # Check to see if the the host is an ETL
    if ( $system_type eq "ETL" ) {
      # Gather the site type ( ACtive or Passive )
      $site_type = get_site_type ( $dbh );
      if ( $site_type eq "Active" ) {
        # Get connections for the NDB and HDS
        $ndb_dbh = connect_to_cluster ( $dbh, 'SX_a1' );
        $hds_dbh = connect_to_hds ( $dbh );
      } elsif ( $site_type eq "Passive" ) {
        # CST 69571 -> Removed Passive Cluster connection. No reason to connect to passive cluster.
      }
    }

    # Get current running processes and set to array
    @running_processes = &sshCmd( $hostname, "/bin/ps auwx");

    # Gather health checks we need to run rom the host configuration file ( JSON )
    @health_checks_to_run = keys $CONFIG->{ 'Health Checks' };
    # Debug Override - Force fping (system) check to fail
    # $hostname = '172.172.172.172' if $hostname eq "usa109st-etl1";

    # Execute single-host healthcheck as normal
    &execute_healthchecks;
  }
} elsif ( $group ne "all" && $group ne "" ) {
  # Load configuration file for health checks parameters
  $CONFIG = load_config( $hostname );

  # Gather health checks we need to run from the host configuration file
  @health_checks_to_run = keys $CONFIG->{ 'Health Checks' };

  # Get current running processes
  @running_processes = &sshCmd( $hostname, "/bin/ps auwx");

  # Connect to the correct database if the host requires it
  if ( $system_type =~ m/(CaseSentry|ETL)/o ) {
    # Establish the connection with the MySQL server
    $dbh = DBI->connect("DBI:mysql:$MP_DB:$hostname", "$DB_USER", "$DB_PASSWORD",{'PrintError' => 0}) or die log_message ( "Database connection not made: $DBI::errstr" );
  }

  # Check to see if the the host is an ETL
  if ( $system_type eq "ETL" ) {
    # Gather the site type ( ACtive or Passive )
    $site_type = get_site_type ( $dbh );
    if ( $site_type eq "Active" ) {
      # Get connections for the NDB and HDS
      $ndb_dbh = connect_to_cluster ( $dbh, 'SX_a1' );
      $hds_dbh = connect_to_hds ( $dbh );
    } elsif ( $site_type eq "Passive" ) {
      # CST 69571 -> Removed Passive Cluster connection. No reason to connect to passive cluster.
    }
  }

  # Check which group we need to run for
  printf "\n======================== %s ========================%s", uc( $group ), "\n\n";
  my @group_health_checks;
  my $time_of_day = strftime "%H:%M", localtime;

  # See which health checks need to be run based on the group that was passed
  foreach my $health_check ( @health_checks_to_run ) {
    my $hc_group = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'group' };
    my $hc_active = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'active' };
    my $time_start = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'time_start' };
    my $time_end = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'time_end' };

    # Check if it's the right time of day to run each healthcheck, if it is
    # we will push each healthcheck that is required to run to the respective
    # array for later comparisson
    if ( ( $time_of_day ge $time_start && $time_of_day le $time_end )|| ( $time_start eq "" && $time_end eq "" ) ) {
      if ( $hc_active eq "true" ) {
        push ( @group_health_checks, $health_check ) if $hc_group eq $group;
      }
    } else {
      log_message ( "[SKIP] $health_check is waiting for $time_start to run", 2, $group ) if $hc_group eq $group;
    }
  }

  foreach my $health_check ( @group_health_checks ) {
    my $hc_group = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'group' };
    my $hc_function = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'function' };
    my $hc_param_1 = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'param_1' };
    my $hc_param_2 = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'param_2' };
    my $hc_param_3 = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'param_3' };

    if ( $group eq "system" ) {
      # Assign the value received from the ping check on the hostname we need to run health checks against
      my $fping_return = &system_check ( $hc_group, $health_check, $hc_function, $hc_param_1, $hc_param_2, $hc_param_3 );
      # Print the summary and exit the script if fping finds the host unresponsive
      exit ( 0 ) if defined $fping_return && $fping_return eq "EXIT";
    } elsif ( $group eq "processes" ) {
      # To make sure that we don't try to test against a downed server, we will check each group and
      # exit the group check if the server is not alive
      my $fping_return = `fping $hostname`;
        chomp ( $fping_return );

      # Determine what to do if fping probe returns alive/dead
      if ( grep ( /alive/, $fping_return ) ) {
        &processes_check ( $hc_group, $health_check, $hc_function, $hc_param_1, $hc_param_2, $hc_param_3 );
      } else {
        print "Fping returned $fping_return -> exiting $group iteration\n";
        log_message ( "[$hostname] fping: $fping_return -> unable to execute health checks for host", 3, "fping" );
      }
    } elsif ( $group eq "application" ) {
      # To make sure that we don't try to test against a downed server, we will check each group and
      # exit the group check if the server is not alive
      my $fping_return = `fping $hostname`;
        chomp ( $fping_return );

      # Determine what to do if fping probe returns alive/dead
      if ( grep ( /alive/, $fping_return ) ) {
        &application_check ( $hc_group, $health_check, $hc_function, $hc_param_1, $hc_param_2, $hc_param_3 );
      } else {
        print "Fping returned $fping_return -> exiting $group iteration\n";
        log_message ( "[$hostname] fping: $fping_return -> unable to execute health checks for host", 3, "fping" );
      }
    } elsif ( $group eq "database" ) {
      # To make sure that we don't try to test against a downed server, we will check each group and
      # exit the group check if the server is not alive
      my $fping_return = `fping $hostname`;
        chomp ( $fping_return );

      # Determine what to do if fping probe returns alive/dead
      if ( grep ( /alive/, $fping_return ) ) {
        &database_check ( $hc_group, $health_check, $hc_function, $hc_param_1, $hc_param_2, $hc_param_3 );
      } else {
        print "Fping returned $fping_return -> exiting $group iteration\n";
        log_message ( "[$hostname] fping: $fping_return -> unable to execute health checks for host", 3, "fping" );
      }
    }
  }
}


#----------------------------------- END SCRIPT LOGIC --------------------------------------


#-------------------------------------- SUBROUTINES ----------------------------------------

sub print_usage {
  print "\n------------------------ USAGE -------------------------\n\n";
  print "Running these healthchecks to see the current system health for a host:\n"
    , "\t[ ./health.pl --hostname=HOSTNAME ]\n\n"
    , "To see the health of a particular group for a hostname:\n"
    , "\t[ ./health --hostname=HOSTNAME --group=GROUP ]\n\n"
    , "** Cron-run is to only be used by the cron job as it provides updates to CCS **\n"
    , "[ ./health.pl --hostname=all --cron-run ]\n\n"
    , "Additional Options:\n\n"
    , "--help                       Display this message for use of script\n"
    , "[ ./health.pl --help ]\n\n"
    , "--group= [ PARAM ]                    Run specific group healthchecks for specified hostname\n"
    , "[ all ]                      Only used with the cron-run execution\n"
    , "[ database -- application -- system -- processes ]\n\n"
    , "--debug                      Enable debugging for detailed information\n"
    , "[ ./health.pl --hostname=HOSTNAME --debug ]\n\n"
    , "--send-clear                 Send a trap to CCS to clear an alarm\n"
    , "[ ./health.pl --hostname=HOSTNAME --send-clear --group=GROUP ]\n\n";
    exit(0);
}

sub print_status {
  my $name = shift;
  my $status = shift;
  my $notes = shift;

  push @group_status, "$status";

  if ( $cron_run ) {
    # Concatinate status and health check name to the trap message if we will
    # need to send an alarm to CCS
    $CCS_trap_contents .= "$status :: $name\n";
  } elsif ( !$cron_run ) {
    if ( $status eq "PASS") {
      print GREEN, "PASS :: " . $name, RESET . "\n\t" . $notes . "\n";
    } elsif ( $status eq "FAIL") {
      print RED, "FAIL :: " . $name, RESET . "\n\t" . $notes . "\n";
    } elsif ( $status eq "UNKNOWN") {
      print BLUE, "UNKNOWN :: " . $name, RESET . "\n\t" . $notes . "\n";
    } else {
      print BLUE, "N/A :: " . $name, RESET . "\n\t" . $notes . "\n";
    }
    # Concatinate status and health check name to the trap message if we will
    # need to send an alarm to CCS
    $CCS_trap_contents .= "$status :: $name\n";
  }
}

sub load_config {
  $hostname = shift;

  my $content;
  my $config_file = $health_directory . "/config/CFG_$hostname.json";

  if ( $hostname ne 'all' ) {
    open ( my $fh, '<', $config_file ) or die "Unable to open $config_file...\nMake sure the config file is created in the proper directory for parsing";
      local $/;
      $content = <$fh>;
    close ( $fh );

    $CONFIG = decode_json ( $content );

    # Load system type and assign to variable or exit the script
    $system_type = $CONFIG->{ 'SystemType' }->{ 'type' } or log_message ( "[$hostname] Unable to set system type", 3, "Load Config" );
      exit ( print "\nUnable to set system type - Check configuration file and error.log\n") if ( !$system_type || $system_type eq '' );
    } else {

    }
    # Load configuration parameters for the host we're going to be checking

  return $CONFIG;

}

sub load_cron_config {
  my $config_file = $health_directory . "/config/CFG_HOSTS.json";

    open ( my $fh, '<', $config_file ) or die "Unable to open $config_file...\nMake sure the config file is created in the proper directory for parsing";
      local $/;
      my $content = <$fh>;
    close ( $fh );

    my $CONFIG = decode_json ( $content );

    # Load configuration parameters for the host we're going to be checking
    my @hosts = $CONFIG->{ 'Hosts' };

  return $CONFIG;
}

sub sshCmd {
  my $hostname = shift;
  my $cmd = shift;

  # invoke a Net::OpenSSH object
  if ( my $ssh = Net::OpenSSH->new ( $hostname, key_path => '/root/.ssh/id_rsa', master_stderr_discard => 1 ) ) {
    # Send the command to the remote host
    if ( my $output = $ssh->capture ( $cmd ) ) {
      return $output;

    } else {
        $ssh->error and log_message ( "[$hostname] Unable to execute remote command: " . $ssh->error, 3 );
    }
  } else {
    $ssh->error and log_message ( "[$hostname] Unable to establish an SSH connection: " . $ssh->error, 3 );
  }
}

sub execute_healthchecks {
  # Execute health checks for the host based on configuration parameters
  $status = "UNKNOWN";
  my @system_check;
  my @processes_check;
  my @application_check;
  my @database_check;
  my $time_of_day = strftime "%H:%M", localtime;

  # Loop through the health checks and gather their associated groups so we can
  # run them based on the group for screen output and sending to CCS via Traps
  foreach my $health_check ( @health_checks_to_run ) {
    my $hc_group = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'group' };
    my $hc_active = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'active' };
    my $time_start = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'time_start' };
    my $time_end = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'time_end' };

    # Check if it's the right time of day to run each healthcheck, if it is
    # we will push each healthcheck that is required to run to the respective
    # array for later comparisson
    if ( ( $time_of_day ge $time_start && $time_of_day le $time_end )|| ( $time_start eq "" && $time_end eq "" ) ) {
      # Check if the health check is set to be active in the config
      if ( $hc_active eq "true" ) {
        push ( @system_check, $health_check ) if $hc_group eq "system";
        push ( @application_check, $health_check ) if $hc_group eq "application";
        push ( @processes_check, $health_check ) if $hc_group eq "processes";
        push ( @database_check, $health_check ) if $hc_group eq "database";
      }
    } else { log_message ( "[SKIP] $health_check is waiting for $time_start to run", 2, $group ); }
  }
  # Check the arrays from above that the healthchecks were pushed to and go through
  # each one that we've determined need to be run
  if ( @system_check ) {
    printf "\n======================== %s ========================%s", uc ( "system" ), "\n\n" if !$cron_run;
    # Add trap header for the group
    $CCS_trap_contents .= "================ SYSTEM ================\n";
    my $fping_return;

    foreach my $health_check ( @system_check ) {
      my $hc_group = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'group' };
      my $hc_function = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'function' };
      my $hc_param_1 = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'param_1' };
      my $hc_param_2 = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'param_2' };
      my $hc_param_3 = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'param_3' };

      # Running the system_check subroutine will execute the fping function first and foremost
      # and return EXIT if the host we're checking is unreachable. fping_return will hold
      # the exit status and if it's found that the hostname is non-responsive we will exit
      # the script altogether since we won't be able to execute the rest of the groups.
      $fping_return = &system_check ( $hc_group, $health_check, $hc_function, $hc_param_1, $hc_param_2, $hc_param_3 );

      # CCS Trap Check - See if we have a failed health check, and send to CCS
      # for the group that's currently being run.
      &CCS_Trap_Check( $hostname, $hc_group, $CCS_trap_contents ) if defined $fping_return && $fping_return eq "EXIT" && defined $cron_run;

      # Print the summary and exit the script if we need to exit the script upon fping finding the host unresponsive
      # when running without the cron iteration
      exit (print "\n================================= SUMMARY =================================\n\n"
            ,"HealthCheck Results: "
            ,RED, "CHECK!  A FAILURE CONDITION EXISTS.  PLEASE INVESTIGATE.\n", RESET
            ,"System Architecture: $system_type\n"
            ,"Site Type: $site_type\n" ) if defined $fping_return && $fping_return eq "EXIT" && !$cron_run;

      # If cron is running - exit the iteration if the host is found to have failed the ping check
      exit (0) if defined $fping_return && $fping_return eq "EXIT" && $cron_run;

      if ( $debug ) {
        print "\n\tJSON Params\n";
        print "\t\tGroup:\t\t$hc_group\n";
        print "\t\tFunction:\t$hc_function\n";
        print "\t\tParam 1:\t$hc_param_1\n";
        print "\t\tParam 2:\t$hc_param_2\n" if $hc_param_2 ne "";
        print "\t\tParam 3:\t$hc_param_3\n" if $hc_param_3 ne "";
      }
    }
    # CCS Trap Check - See if we have a failed health check, and send to CCS
    # for the group that's currently being run.
    &CCS_Trap_Check( $hostname, 'system', $CCS_trap_contents ) if defined $cron_run;
      # Remove contents from variable to be re-used for other groups
      undef ( $CCS_trap_contents );
  } if ( @processes_check ) {
    printf "\n======================== %s ========================%s", uc( "processes" ), "\n\n" if !$cron_run;
    # Add trap header for the group
    $CCS_trap_contents .= "================ PROCESSES ================\n";
    foreach my $health_check ( @processes_check ) {
      my $hc_group = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'group' };
      my $hc_function = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'function' };
      my $hc_param_1 = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'param_1' };
      my $hc_param_2 = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'param_2' };
      my $hc_param_3 = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'param_3' };

      &processes_check ( $hc_group, $health_check, $hc_function, $hc_param_1, $hc_param_2, $hc_param_3 );

      if ( $debug ) {
        print "\n\tJSON Params\n";
        print "\t\tGroup:\t\t$hc_group\n";
        print "\t\tFunction:\t$hc_function\n";
        print "\t\tParam 1:\t$hc_param_1\n";
        print "\t\tParam 2:\t$hc_param_2\n" if $hc_param_2 ne "";
        print "\t\tParam 3:\t$hc_param_3\n" if $hc_param_3 ne "";
      }
    }
    # CCS Trap Check - See if we have a failed health check, and send to CCS
    # for the group that's currently being run.
    &CCS_Trap_Check( $hostname, 'processes', $CCS_trap_contents )if defined $cron_run;
      # Remove contents from variable to be re-used for other groups
      undef ( $CCS_trap_contents );
  } if ( @application_check ) {
    printf "\n======================== %s ========================%s", uc ( "application" ), "\n\n" if !$cron_run;
    # Add trap header
    $CCS_trap_contents .= "================ APPLICATION ================\n";
    foreach my $health_check ( @application_check ) {
      my $hc_group = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'group' };
      my $hc_function = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'function' };
      my $hc_param_1 = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'param_1' };
      my $hc_param_2 = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'param_2' };
      my $hc_param_3 = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'param_3' };

      &application_check ( $hc_group, $health_check, $hc_function, $hc_param_1, $hc_param_2, $hc_param_3 );

      if ( $debug ) {
        print "\tJSON Params\n";
        print "\t\tGroup:\t\t$hc_group\n";
        print "\t\tFunction:\t$hc_function\n";
        print "\t\tParam 1:\t$hc_param_1\n";
        print "\t\tParam 2:\t$hc_param_2\n" if $hc_param_2 ne "";
        print "\t\tParam 3:\t$hc_param_3\n" if $hc_param_3 ne "";
      }
    }
    # CCS Trap Check - See if we have a failed health check, and send to CCS
    # for the group that's currently being run.
    &CCS_Trap_Check( $hostname, 'application', $CCS_trap_contents ) if defined $cron_run;
      # Remove contents from variable to be re-used for other groups
      undef ( $CCS_trap_contents );
  } if ( @database_check ) {
    if ( $system_type eq "ETL" && $site_type eq "Active" ) {
      printf "\n======================== %s ========================%s", uc ( "database" ), "\n\n" if !$cron_run;
      # Add trap header for the group
      $CCS_trap_contents .= "================ DATABASE ================\n";
      foreach my $health_check ( @database_check ) {
        my $hc_group = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'group' };
        my $hc_function = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'function' };
        my $hc_param_1 = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'param_1' };
        my $hc_param_2 = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'param_2' };
        my $hc_param_3 = $CONFIG->{ 'Health Checks' }->{ $health_check }->{ 'param_3' };

        &database_check ( $hc_group, $health_check, $hc_function, $hc_param_1, $hc_param_2, $hc_param_3 );

        if ( $debug ) {
          print "\n\tJSON Params\n";
          print "\t\tGroup:\t\t$hc_group\n";
          print "\t\tFunction:\t$hc_function\n";
          print "\t\tParam 1:\t$hc_param_1\n";
          print "\t\tParam 2:\t$hc_param_2\n" if $hc_param_2 ne "";
          print "\t\tParam 3:\t$hc_param_3\n" if $hc_param_3 ne "";
        }
      }
      # CCS Trap Check - See if we have a failed health check, and send to CCS
      # for the group that's currently being run.
      &CCS_Trap_Check( $hostname, 'database', $CCS_trap_contents ) if defined $cron_run;
        # Remove contents from variable to be re-used for other groups
        undef ( $CCS_trap_contents );
      }
  }

  # Summarize system health status
  my @check = grep (/FAIL/, @group_status);
  if ( @check && !$cron_run ) {
    print "\n================================= SUMMARY =================================\n\n";
    print "HealthCheck Results: ";
      print RED, "CHECK! A FAILURE CONDITION EXISTS.  PLEASE INVESTIGATE.\n", RESET;
    print "System Architecture: $system_type\n";
      print "Sending CCS Alarm\n";
    print "DataColl Site Type : $site_type\n" if $site_type;
  } elsif ( !$cron_run ) {
    print "\n================================= SUMMARY =================================\n";
    print "HealthCheck Results: ";
    print GREEN, "OK.\n", RESET;
    print "System Architecture: $system_type\n";
    print "DataColl Site Type : $site_type\n" if $site_type;
  }
}

sub get_site_type {
  my $dbh = shift;

  if ( defined $dbh ) {
    my $query = "SELECT CONCAT(UCASE(LEFT(`value`, 1)), SUBSTRING(`value`, 2)) FROM `FS`.`SextantConfig` WHERE `parm` = 'Local site type'";
    if ( my $sth = $dbh->prepare( $query ) ) {
      if ( $sth->execute() ) {
        my $site_type;
        if ( $sth->bind_columns( \$site_type ) ) {
          if ( $sth->fetch ) {

            return $site_type;
          } else {
            log_message ( " -> could not fetch data\n\t[System Msg] -> $DBI::errstr" );
          }
        } else {
          log_message ( " -> unable to bind column \$site_type\n\t[System Msg] -> $DBI::errstr" );
        }
      }
      log_message( " -> cannot execute query: \"$query\"\n\t[System Msg] -> $DBI::errstr", 3, "get_site_type" );
    } else {
      log_message ( " -> cannot prepare query: \"$query\"\n\t[System Msg] -> $DBI::errstr", 3, "get_site_type" );
    }
  } else {
    log_message ( "-> unable to get site type, dbh handle not defined", 3, "get_site_type" );
  }
}

sub application_check {
  my $group = shift;
  my $health_check = shift;
  my $function = shift;
  my $param_1 = shift;
  my $param_2 = shift;
  my $param_3 = shift;

  my $status = "UNKNOWN";
  my $notes = "";

  if ( $function eq "checkLoginPage" ) {
    my $location = '/home/sextant-support/';
    my $process_identifier;
      $process_identifier = '_sextant' if ($health_check =~ m/sextant/io);
      $process_identifier = '_pentaho' if ($health_check =~ m/pentaho/io);

    # Retrieve web status using the nagios plugin
    my $web_status = `curl -kIs https://$hostname/$param_1 | head -1`;
    chomp( $web_status );

    if( $web_status =~ m/200 OK/io ) {
      $status = "PASS";
      # Check if a lock file exists. If it does, let's remove it since we passed the check this time around
      check_and_clean_lockfile( $hostname . $process_identifier, $group ) if $status eq "PASS";
      $notes = "https://${hostname}${param_1} is responding";

    } else {
        log_message( "[$hostname][$health_check] 'OK' was not found -> Trying again", 2, $group );
      sleep( 10 );
      # Check the status of the page again to confirm the alarm
      $web_status = `curl -kIs https://$hostname/$param_1 | head -1`;
      chomp( $web_status );
        log_message( "[$hostname][$health_check] Second try return: $web_status", 1, $group );
        $notes = "https://$hostname$param_1 is not responding" if $status eq "UNKNOWN";
      if ( $web_status =~ m/200 OK/io ){
        $status = "PASS";
        # Check if a lock file exists. If it does, let's remove it since we passed the check
        check_and_clean_lockfile( $hostname . $process_identifier, $group );
          log_message( "[$hostname][$health_check] Status: $status", 1, $group ) if $status eq "PASS";

      } else {
          log_message( "[$hostname][$health_check] 'OK' was not found in the return for the second time", 2, $group );
        # Check for lock file. If it's not present create it and return UNKNOWN, if it's already created return FAIL
        $status = check_for_lock_file( $hostname . $process_identifier, $group );
        $notes = "https://${hostname}${param_1} is NOT responding" if $status eq "FAIL";
      }
    }

    &print_status ( $health_check, $status, $notes );

    if ( $debug ) {
      print "\n--------  --------  --------\n";
      print " Page status: " . $web_status . "\n--------  --------  --------\n\n";
    }
  }
}

sub database_check {
  my $group = shift;
  my $health_check = shift;
  my $function = shift;
  my $param_1 = shift;
  my $param_2 = shift;
  my $param_3 = shift;

  my $status = "UNKNOWN";
  my $notes = "";

  if ( $function eq "ETLStaleData" ) {
    # If this is the Active ETL then we check here first against the etl_process_signals records, then move on to the HDS and NDB comparison if it fails
    if ( $site_type eq "Active" ) {

      # Check the current time to compare and determine which threshold should be used below
      my $current_time = POSIX::strftime "%H:%M:%S", localtime;

      # During work hours set the threshold to 60 minutes to address gaps in a timely fashion since reports are affected by gaps
      # If we are outside of work hours, the threshold remains the default value found in the config file (7200 sec)
      $param_3 = '3600' if $current_time gt '08:00:00' && $current_time lt '17:00:00';
        # Test etl_process_signals check and logging
        # $param_3 = '10' if $param_2 eq "Agent_Half_Hour";
      # Gather data from our local DB to check for stale data
      my %data = query_etl_process_signals( $param_1, $param_2 );
        # Current time - timestamp in etl process signals interval
        my $difference =  $data{difference} if $data{difference};
        # DateTime for etl process signals interval
        my $datetime =  $data{datetime} if $data{datetime};

      # If we return data from etl_process_signals, we'll go ahead and compare it to see if we're
      # collecting, if not then we'll go ahead to the NDB and HDS to check their values. If we can't
      # do that either then we need to fail the check since we are not gathering data.

      if ( defined $difference && defined $datetime ) {
        # If the difference is less than the threshold (either 3600-businiess hours, 7200 default) let's go ahead
        # and set the status to PASS
        if ( $difference <= $param_3 ) {
          $status = "PASS";
          # Check for lockfile. If it exists -> remove it since the check passed this iteration
          check_and_clean_lockfile( $param_2, $group );
          $notes = "Difference between etl_process_signals: $difference seconds";
            # Detailed output if the debug flag is passed
            $notes = "Difference between etl_process_signals: $difference seconds\n\tThreshold: $param_3 seconds\n\tDateTime(etl_process_signals): $datetime" if $debug;
        } elsif ( $difference > $param_3 ) {
          # This table is a one-off so we are not going to check the NDB and HDS comparisson for it
          if ( $param_2 eq "Bundle_Attribute_Call_Type_Half_Hour" ) {
            $status = "FAIL";
            # Print detailed output if the etl_process_signals check fails
            $notes = "Difference between etl_process_signals: $difference seconds\n\tThreshold: $param_3 seconds\n\tDateTime(etl_process_signals): $datetime";
          # For all other tables we've checked against
          } else {

            # Check and compare NDB and HDS values and set status accordingly
              log_message( "[$param_2] FAILED the etl_process_signals check", 2, $group );
              log_message( "\tStatus:      $status", 1, $group );
              log_message( "\tTimestamp:   $datetime", 1, $group );
              log_message( "\tDifference:  $difference seconds", 1, $group );
              log_message( "\tThreshold:   $param_3", 1, $group );
              log_message( "Comparing HDS and NDB datetimes to determine if the alarm is valid", 1, $group);

            # Retrieve the data from the cluster
            my @ndb_dt = query_cluster( $ndb_dbh, $param_2 ) or log_message ( "Unable to retrieve NDB datetime data", 3, $group );
            # Retrieve the data from the HDS
            my @hds_dt = query_hds( $hds_dbh, $param_2 ) or log_message ( "Unable to retrieve HDS datetime data", 3, $group );

            my $unknown_status;

            # Check if we received the data from the NDB
            if ( not defined $ndb_dt[0] || $ndb_dt[0] eq "" ) {
                log_message ( "[$param_2] NDB Query :: Attempt 1 -> NDB datetime returned null. Re-running to try to get the value", 2, $group );
              # If we don't get anything the first time, we'll try again to make sure (originally implemented due to LWTE)
              @ndb_dt = query_cluster( $ndb_dbh, $param_2 );
              if ( not defined $ndb_dt[0] || $ndb_dt[0] eq "" ) {
                  log_message ( "[$param_2] NDB Query :: Attempt -> 2 NDB datetime returned null again. Setting status to unkown to avoid a false alarm", 3, $group );
                my $unknown_status = 1;
              }
            }

            # Check if we received the data from the HDS
            if ( not defined $hds_dt[0] || $hds_dt[0] eq "" ) {
                log_message ( "[$param_2 ]HDS Query :: Attempt 1 -> HDS datetime returned null. Re-running to try and get the value", 2, $group );
              @hds_dt = query_hds( $hds_dbh, $param_2 );
              if ( not defined $hds_dt[0] || $hds_dt[0] eq "" ) {
                  log_message( "[$param_2] HDS Query :: Attempt 2] -> HDS datetime returned null again. Setting status to unknown to avoid a false alarm", 3, $group );
                my $unknown_status = 1;
              }
            }

            if ( @ndb_dt && @hds_dt ) {
              # Set the difference between the two times
              my $diff = $hds_dt[0] - $ndb_dt[0];
                # Test HDS NDB comparisson failure and logging
                # $diff = '7500' if $param_2 eq "Agent_Half_Hour";
              if ( $diff < $param_3 ) {
                # Check for the lockfile. If it's found we'll remove it since we passed this iteration with the HDS comparisson
                  check_and_clean_lockfile( $param_2, $group );
                $status = "PASS";
                  log_message( "[$param_2] PASSED the NDB and HDS comparisson", 1, $group) if $status eq "PASS";
              } elsif ( $diff >= $param_3 ) {
                  log_message( "[$param_2] FAILED the NDB and HDS comparisson", 2, $group );
                log_message( "\tStatus:      $status", 1, $group );
                log_message( "\tHDS:         $hds_dt[0] :: $hds_dt[1]", 1, $group );
                log_message( "\tNDB:         $ndb_dt[0] :: $ndb_dt[1]", 1, $group );
                log_message( "\tDifference:  $diff", 1, $group );
                log_message( "\tThreshold:   $param_3", 1, $group );

                # Check for lockfile and set FAIL if one is already created
                $status = check_for_lock_file( $param_2, $group );
              }

              $status = "UNKNOWN" if defined $unknown_status;
              $notes = "Difference between NDB and HDS: $diff seconds\n\tTheshold: $param_3 seconds\n\tNDB: $ndb_dt[1]\n\tHDS: $hds_dt[1]";

            } else {
              $status = "FAIL";
              $notes = "Issues with retrieving data from HDS / NDB - Needs investigation";
                log_message("[$param_2] NDB or HDS did not return data to complete the evaluation", 2, $group );
            }
          }
        }
        $status = "N/A" if $active;
      }
    }
  }
  # Print status and details for the healthcheck
  print_status( $health_check, $status, $notes );
}

sub system_check {
  my $group = shift;
  my $health_check = shift;
  my $function = shift;
  my $param_1 = shift;
  my $param_2 = shift;
  my $param_3 = shift;

  my $status = "UNKOWN";
  my $notes = "";

  if ( $function eq "fping" ) {
    # Let's ping the hostname from the ETL ( where the health checks are run )
    my $ping_return = `fping $hostname`;
      # Remove any whitespace / carriage returns from the output
      chomp( $ping_return );
    # Parse the return and check if param_1 is found
    #   Param_1 = alive
    my $ping_status = grep ( /$param_1/, $ping_return );

    # The above grep will return a 1 if $param_1 was found, 0 if it is not found
    # Set status and notes depending on if we pass the $ping_status
    ( $status = "PASS", $notes = "$hostname returned alive" ) if $ping_status == 1;
    ( $status = "FAIL", $notes = "$hostname returned unreachable" ) if $ping_status != 1;
      log_message ( "[$hostname][$health_check] Ping returned value -> $ping_return", 2, $group ) if $status eq "FAIL";

    &print_status ( $health_check, $status, $notes );
      return "EXIT" if $status ne "PASS";
      return "clear" if $status eq "PASS";

    if ( $debug ) {
      print "\n --------  --------  -------- \n";
      print " Ping return status:   alive\n --------  --------  --------\n\n" if $ping_status == 1;
      print " Ping return status:  unreachable\n --------  --------  --------\n\n" if $ping_status != 1;
    }
  }
  elsif ( $function eq "CheckUptime" ) {
    my $threshold = $param_1 || 30;
    my $upSeconds = &SshCmd( $hostname, "/bin/cat /proc/uptime | /bin/grep -o '^[0-9]\\+'");
    chomp($upSeconds);
    my $upMinutes = int(($upSeconds / 60));

    $status = "PASS" if $upMinutes >= $threshold;
    $status = "FAIL" if $upMinutes < $threshold;
    $notes = "System uptime for $hostname is $upMinutes minutes, threshold is $threshold minutes";
  }
  elsif ( $function eq "CPUwarn" ) {
    # Let's gather the number of processors we have for the host we're checking
    my $num_cpus = &sshCmd( $hostname, "/bin/cat /proc/cpuinfo | /bin/grep processor | /usr/bin/wc -l" );
      chomp( $num_cpus );
    # Now we'll set the threshold.
    # Theshold will be $param_1 if it is set, or if the param was not set threshold will be number of processors - 1
    my $cpu_thresh = ( $param_1 ? $param_1 : ( $num_cpus - 1));
    # Let's get the load average for the host we're checking
    my $load = &sshCmd( $hostname, "/bin/cat /proc/loadavg | /usr/bin/awk '{print \$2}'" );
      chomp( $load );

    # Set status to PASS if the theshold is not breached
    $status = "PASS" if $load < $cpu_thresh;
      # Check for a lock file and remove it if it exists since we passed this iteration
      check_and_clean_lockfile( $hostname . "_" . $function, $group ) if $status eq "PASS";
    # If the theshold is breached, check for a lock file
    # If one doesn't exist, create it and return a status of UNKNOWN
    # If one already exists, status returns FAIL
    $status = check_for_lock_file( $hostname . "_" . $function, $group ) if $load >= $cpu_thresh;
      log_message( "[$hostname][$health_check] Status: $status -> Next healthcheck iteration will verify if this is a true alarm", 2, $group ) if $status eq "UNKNOWN";
      log_message( "[$hostname][$health_check] Status: $status -> Load average -> $load\tThreshold -> $cpu_thresh", 2, $group ) if $status eq "FAIL";
    $notes = "Load average for the last 5 minutes is $load, the threshold is $cpu_thresh";

    &print_status ( $health_check, $status, $notes );
    if ( $debug ) {
      print "\nTest:            " . $health_check . "\n";
      print "Num CPU's:       " . $num_cpus . "\n";
      print "Status:          " . $status . "\n";
      print "Notes:           " . $notes . "\n\n";
    }
  }
  elsif ( $function eq "DiskSpace") {
    my $disk_info = &sshCmd ($hostname, "/bin/df -BG / | /bin/grep dev | /usr/bin/head -1 | /usr/bin/awk '{print \$1\",\"\$2\",\"\$3}'");
      $disk_info =~ s/(\n|G)//go;
      my ( $drive_name, $drive_size, $drive_used ) = split(/,/, $disk_info);
      my $usage = ( ( $drive_used / $drive_size ) * 100 );

      # Set status to PASS if the threshold is not breached
      $status = "PASS" if $usage < $param_1;
      # If we PASS, check for lockfiles and clean them
      check_and_clean_lockfile( $hostname . "_" . $function, $group ) if $status eq "PASS";
      # If the theshold is breached, check for a lock file
      # If one doesn't exist, create it and return a status of UNKNOWN
      # If one already exists, status returns FAIL
      $status = check_for_lock_file( $hostname . "_" . $function, $group ) if $usage >= $param_1;
        log_message ( "[$hostname][$health_check] Status: $status -> Next healthcheck iteration will verify if this is a true alarm", 2, $group ) if $status eq "UNKNOWN";
        log_message ( "[$hostname][$health_check] Statue: $status -> $health_check usage has surpassed the threshold :: Usage " . int( $usage ) . "% :: Theshold $param_1%", 2, $group ) if $status eq "FAIL";
      $notes = "Drive usage is " . int( $usage ) . "%, the threshold is $param_1";

      &print_status ( $health_check, $status, $notes );
    if ( $debug ) {
      print "Test:            " . $health_check . "\n";
      print "Drive:           " . $drive_name . "\n";
      print "Drive Size:      " . $drive_size . "\n";
      print "Drive Used:      " . $drive_used . "\n";
      print "Status:          " . $status . "\n";
      print "Notes:           " . $notes . "\n\n";
    }
  }
  elsif ( $function eq "memUsage" ) {
    # Gather memory information from the host we're checking
    my $free_results = &sshCmd ( $hostname, "/usr/bin/free -o | /bin/egrep -i -e '^$param_1'");
      chomp( $free_results );
    # parse and assign the respective variable to the data split by spaces
    my ( $mem_name, $total, $used, $free ) = split( " ", $free_results );

    # If param_3 is not empty, is defined, and is set to cached we'll perform the cached check
    if( defined $param_3 && $param_3 ne "" && $param_3 eq "cached" ) {
      my $cached_result = &sshCmd( $hostname, "/usr/bin/free | /bin/egrep -i -e 'buffers/cache' | /usr/bin/awk '{print \$3}'");
          chomp( $cached_result );
      my $usage = ( ( $cached_result / $total ) *100 );

      $status = "PASS" if $usage < $param_2;
      # If we PASS, check for lockfiles and clean them
      check_and_clean_lockfile ( $hostname . "_" . $function . "_" . $param_1, $group ) if $status eq "PASS";
      # If the theshold is breached, check for a lock file
      # If one doesn't exist, create it and return a status of UNKNOWN
      # If one already exists, status returns FAIL
      $status = check_for_lock_file ( $hostname . "_" . $function . "_" . $param_1, $group ) if $usage >= $param_2;
        log_message ( "[$hostname][$health_check] Status :: $status -> Next iteration will verify if this is a true alarm", 2, $group ) if $status eq "UNKNOWN";
        log_message ( "[$hostname][$health_check] Status :: $status -> $health_check surpassed the threshold :: Used " . int( $usage ) . "% :: Threshold $param_2", 2, $group ) if $status eq "FAIL";
      $notes = uc( $param_1 ) . " utilization is currently at " . int( $usage ) . "%, the threshold is $param_2%";

    # If we don't need to run the cached check, let's run the standard memory check
    } else {
      my $usage = ( ( $used / $total ) * 100 );

      $status = "PASS" if $usage < $param_2;
      # If we PASS, check for lockfiles and clean them
      check_and_clean_lockfile ( $hostname . "_" . $function . "_" . $param_1, $group ) if $status eq "PASS";
      # If the theshold is breached, check for a lock file
      # If one doesn't exist, create it and return a status of UNKNOWN
      # If one already exists, status returns FAIL
      $status = check_for_lock_file( $hostname . "_" . $function . "_" . $param_1, $group ) if $usage >= $param_2;
        log_message ( "[$hostname][$health_check] $status :: Status -> Next iteration will verify if this is a true alarm", 2, $group ) if $status eq "UNKNOWN";
        log_message ( "[$hostname][$health_check] $status :: Status -> $health_check surpassed the threshold :: Used " . int( $usage ) . "% :: Threshold $param_2", 2, $group ) if $status eq "FAIL";
      $notes = uc( $param_1 ) . " utilization is currently at " . int( $usage ) . "%, the threshold is $param_2%";
    }

    &print_status ( $health_check, $status, $notes );

    if ( $debug ) {
      print "Test:            " . $health_check . "\n";
      print "Total:           " . $total . "\n";
      print "Used:            " . $used . "\n";
      print "Free:            " . $free . "\n";
      print "Notes:           " . $notes . "\n\n";
    }
  }
  elsif ( $function eq "CheckCDR" ) {
    # Path to CDR directory
    my $CDR_path = $param_1 || '/var/www/CaseSentry/tmp/CDR';
    # Number of files in temp dir triggering failure
    my $threshold = $param_2 || 50;
    my $fileCount = 0;

    # Let's check if the CDR directory exists
    if ( -e $CDR_path ) {
      # Scan the directory for items with "CDR"
      opendir( CDRDIR, $CDR_path );
        my @pubDirs = grep { /^CDR_/ } readdir( CDRDIR );
        closedir CDRDIR;
      foreach my $pubDir ( @pubDirs ) {
        opendir( PUBDIR, $CDR_path . $pubDir ) or next;
        # Check the directory for items in the regex search
        my $cdrFiles = grep { /^c[dm]r/ && -f $CDR_path . $pubDir . "/" . $_ } readdir(PUBDIR);
        closedir PUBDIR;
        $fileCount += $cdrFiles;
      }
      # We PASS if the filecount doesn't breach the threshold
      $status = "PASS" if ( $fileCount < $threshold );
        # If we PASS, check for lock files and remove them
        check_and_clean_lockfile ( $function, $group ) if $status eq "PASS";
        # If the theshold is breached, check for a lock file
        # If one doesn't exist, create it and return a status of UNKNOWN
        # If one already exists, status returns FAIL
      $status = check_for_lock_file ( $function, $group ) if ( $fileCount >= $threshold );
        log_message ( "[$hostname][$health_check] Alarm has been triggered :: Filecount -> $fileCount Thesh -> $threshold :: Next iteration will determine if the alarm is valid", 2, $group ) if $status eq "UNKNOWN";
        log_message ( "[$hostname][$health_check] Status: $status -> File Count: $fileCount -> Threshold: $threshold", 2, $group ) if $status eq "FAIL";
      $notes = "There are currently $fileCount files in the import directory";
    } else {
      # If the CDR directory is not found, we FAIL
      $status = "FAIL";
      $notes = "CDR import directory: $CDR_path does not exist";
    }

    &print_status ( $health_check, $status, $notes );
    if ( $debug ) {
      print "Test:            " . $health_check . "\n";
      print "Param_1:         " . $param_1 . "\n";
      print "Param_2:         " . $param_2 . "\n";
      print "Status:          " . $status . "\n";
      print "Notes:           " . $notes . "\n\n";
    }
  }
  # Health checks run on ETL and the 30-day archive of exports also reside on
  # ETL, so checking whether the current day's export is on disk should be a
  # sufficient check whether the export process ran.
  # The export runs once at 12:30am and health checks run multiple times a
  # day. To account for this and any additional processing time required by
  # the export, assume 2am as the earliest possible time to check for the
  # current day.
  elsif ( $function eq "DailySextantExportCheck") {
    # Determine if the ETL is active/passive to see if we can run this check
    if ( $site_type eq "Active" ) {
      my %csConfig = ();
      my $sql = "SELECT `parm`,`value` FROM `CaseSentry`.`CaseSentryConfig` WHERE `parm` IN('sextant-daily-filedirectory','sextant-daily-ftpserver','sextant-daily-ftpuser','sextant-daily-ftpdirectory')";
      my $query = $dbh->prepare($sql);
      $query->execute();
      while (my $row = $query->fetchrow_hashref())
      {
        $csConfig{$row->{parm}} = $row->{value};
      }

      my $exportDate = POSIX::strftime("%Y%m%d", localtime);
      opendir(EXPORT, $csConfig{'sextant-daily-filedirectory'});
      my @exportFiles = grep { /SextantDailyExport $exportDate/ } readdir( EXPORT );
      closedir EXPORT;

      if ( !scalar ( @exportFiles ) ) {
        $notes = "Daily Export file does not exist";
          # Since the file does not exist, check for a lock file
          # If one doesn't exist, create it and return a status of UNKNOWN
          # If one already exists, status returns FAIL
            log_message("[$hostname][$health_check] SextantDailyExport $exportDate does not exist in $csConfig{'sextant-daily-filedirectory'}", 2, $group);
          check_for_lock_file ( $function, $group );
      } else {
        my $fileSize = -s $csConfig{ 'sextant-daily-filedirectory' }. '/' . $exportFiles[0];
        if ( !$fileSize ) {
          $notes = "Daily Export file has zero length";
            # Check for a lock file, create it if none one isn't found and set status to UNKNOWN, if found status returns FAIL
              log_message("[$hostname][$health_check] SextantDailyExport $exportDate has a file size of 0", 2, $group);
            check_for_lock_file ( $function, $group );
        } else {
          # Check file on FTP server
            log_message ( "[$hostname][$health_check] Checking for SextantDailyExport $exportDate on $csConfig{'sextant-daily-ftpserver'} in the $csConfig{'sextant-daily-ftpdirectory'} Archive directory" , 1, $group );
          my $cmd = 'echo "ls -l ' . $csConfig{'sextant-daily-ftpdirectory'} . 'Archive" | sftp -b - ' . $csConfig{'sextant-daily-ftpuser'} . '\@' . $csConfig{'sextant-daily-ftpserver'} . " | grep \'SextantDailyExport $exportDate' | awk \'{print \$5}\'";
          my @res = split /\n/, `$cmd`;
          my $match_found = 'no';
          foreach my $size ( @res ) {
            $match_found = 'yes' if $size == $fileSize;
          }
          my $files = join ', ', @res;

          if ( $match_found eq 'no' ) {
            $notes = "Daily Export file on FTP Server does not exist or does not match local file";
              # Check for a lock file, and remove it if it is found
                log_message ( "[$hostname][$health_check] Unable to locate the file on the FTP Server that matches our local offload file", 2, $group );
              check_for_lock_file ( $function, $group );
          } else {
            $status = "PASS";
            $notes = "DSV Offload check passed";
            # If we PASS, check for lock files and remove them
              check_and_clean_lockfile ( $health_check, $group ) if $status eq "PASS";
          }
        }
      }
      &print_status ( $health_check, $status, $notes );
    }
  }
}

sub processes_check {
  my $group = shift;
  my $health_check = shift;
  my $function = shift;
  my $param_1 = shift;
  my $param_2 = shift;
  my $param_3 = shift;

  my $status = "UNKNOWN";
  my $notes = "";

  if ( $function eq "checkProcess") {
    # Check if $param_1 exists in the current list of proceeses gathered
    my @process_to_check = grep(/$param_1/, @running_processes);
      if ( @process_to_check ) {
        $status = "PASS";
      } else {
        $status = "FAIL";
        log_message ( "[$hostname][$function] $param_1 not found during processes check", 2, $group ) if $status eq "FAIL";
      }

      # If $status passes, set notes to print that it 'is running', if not notes will pring 'not running'
      $notes = $status eq "PASS" ? "Process \"$param_1\" is running" : "Process \"$param_1\" is  not running";

      &print_status ( $health_check, $status, $notes );

  } elsif ( $function eq "checkTCP" ) {
    # Test TCP for the param passed in for the health check
    my $tcp_stat = &sshCmd( $hostname, "/usr/lib/nagios/plugins/check_tcp -H $param_2 -p $param_3");
      chomp( $tcp_stat );

    if ( $tcp_stat =~ m/TCP OK/io ) {
      $status = "PASS";
    } else {
      $status = "FAIL";
        log_message( "[$hostname][$health_check] $status :: TCP check returned $tcp_stat", 2, $group ) if $status eq "FAIL";
    }

    $notes = "TCP Port $param_3 is responding on host $param_2" if $status eq "PASS";
    $notes = "TCP Port $param_3 is NOT responding on host $param_2" if $status eq "FAIL";

    &print_status ( $health_check, $status, $notes );

  } elsif ( $function eq "ETLDaemonRestartCheck" ) {
    # param_1: daemon path
    # param_2: time to go back in seconds
    # param_3: restart threshold
    use Time::Local;
    my $timestamp;
    my %monthMap = ('Jan'=>0, 'Feb'=>1, 'Mar'=>2, 'Apr'=>3, 'May'=>4, 'Jun'=>5, 'Jul'=>6, 'Aug'=>7, 'Sep'=>8, 'Oct'=>9, 'Nov'=>10, 'Dec'=>11);
    my $now = time;
    my $restartCount = 0;
    my $restartFound = 0;
    $status = "PASS";
    $notes = '';
    my @sxtLog = split "\n", &sshCmd($hostname, "/usr/bin/tail -n $param_2 /var/log/sextant_monitor.log");
    @sxtLog = reverse @sxtLog;

    foreach my $line (@sxtLog) {
      if ($line =~ /^\[[^ ]+ ([^ ]+) +([^ ]+) ([^:]+):([^:]+):([^ ]+) ([^\]]+)\]/) {
        $timestamp = timelocal($5, $4, $3, $2, $monthMap{$1}, $6);
        if ($timestamp < $now - $param_2) {
          last;
        } else {
          if ($restartFound) {
            $restartCount++;
            $restartFound = 0;
          }
        }
      } else {
        if ($line =~ /$param_1/) {
          if ( $line =~ /--init-restarted/ ) {
            $restartFound = 1;
          }
        }
      }

      if ($restartCount >= $param_3) {
        $status = "FAIL";
        $notes = "$param_1 has restarted $restartCount times in the last " . ($param_2 / 60) . " minutes on $hostname";
      } else {
        $notes = ( "$param_1 has not restarted recently" );
      }
    }
    log_message ( "[$hostname][$health_check] $param_1 has restarted $restartCount times", 2, $group ) if $status eq "FAIL";
    &print_status ( $health_check, $status, $notes );
  }
}

sub connect_to_cluster {
  my $dbh = shift;
  my $site = shift;

  if ( defined $dbh ) {
    my $query = "SELECT `perl_driver`, `db_name`, `hostname`, `user`, `pw` FROM `FS`.`sextant_db_info` WHERE `name` = \'" . $site . "\' AND `enabled` = 'Y'";

    if ( my $sth = $dbh->prepare( $query ) ) {
      if (   $sth->execute() ) {
        my ($driver, $db, $host, $user, $pw);

        if ( $sth->bind_columns(\$driver, \$db, \$host, \$user, \$pw) ) {
          if ( $sth->fetch ) {
            if ( my $db_conn = DBI->connect("DBI:$driver:database=$db;host=$host", $user, $pw) ) {

              return $db_conn or log_message ( "unable to return connection", 3, "connect_to_cluster" );

            } else {
              log_message (" -> cannot connect to ndb load balancer\n\t[System Msg] -> $DBI::errstr", 3, "connect_to_cluster");
            }
          } else {
            log_message(" -> unable to fetch data\n\t[System Msg] -> $DBI::errstr", 3, "connect_to_cluster");
          }
        } else {
          log_message (" -> unable to bind columns and values\n\t[System Msg] -> $DBI::errstr", 3, "connect_to_cluster");
        }
      } else {
        log_message (" -> cannot execute query \"$query\"\n\t[System Msg] -> $DBI::errstr", 3, "connect_to_cluster");
      }
    } else {
      log_message(" :: connect_to_cluster] -> cannot prepare query: $query\n\t[System Msg] -> $DBI::errstr");
    }
  } else {
    log_message ( " -> unable to connect to cluster: dbh file handle is not defined", 3, "connect_to_cluster")
  }
}

sub connect_to_hds {
  my $dbh = shift;

  if ( defined $dbh ) {
    my $query = "SELECT `perl_driver`, `hostname`, `user`, `pw`, `db_name`, `port` FROM `FS`.`sextant_db_info` WHERE `name` = 'HDS_1' AND `enabled` = 'Y' AND `connect_order` = (SELECT `value` FROM  `FS`.`SextantConfig` WHERE `parm` = 'Historical')";
    if ( my $sth = $dbh->prepare( $query ) ) {
      if (  $sth->execute() ) {
        my ( $driver, $db, $host, $user, $pw, $port );

        if ( $sth->bind_columns(\$driver, \$host, \$user, \$pw, \$db, \$port) ) {
          if (   $sth->fetch ) {
            $ENV{'TDSVER'} = '8.0';
            $ENV{'TDSPORT'} = '1433';

            my $db_conn = DBI->connect("DBI:$driver:database=$db;server=$host;port=$port", $user, $pw) or log_message (" -> cannot connect to HDS\n[System Msg] -> $DBI::errstr", 3, "connect_to_hds");

            return $db_conn or log_message ( " -> unable to return connection", 3, "connect_to_hds" );

          } else {
            log_message(" -> unable to fetch HDS connect parameters\n", 3, "connect_to_hds");
          }
        } else {
          log_message (" -> unable to bind columns and values", 3, "connect_to_hds");
        }
      } else {
        log_message(" -> unable to execute query: \"$query\"", 3, "connect_to_hds");
      }
    } else {
      log_message(" -> unable to prepare query: \"$query\"", 3, "connect_to_hds");
    }
  } else {
    log_message ( "-> unable to connect to hds: dbh file handle isn't set", 3, "connect_to_hds" );
  }
}

sub query_etl_process_signals {
  my $param_1 = shift;
  my $param_2 = shift;
  my $difference;
  my $datetime;
  my %data = ("difference" => "", "datetime" => "");

  if ( defined $dbh ) {
    my $sql = "SELECT (UNIX_TIMESTAMP(NOW()) - `timestamp`), FROM_UNIXTIME(`timestamp`) FROM `FS`.`etl_process_signals` WHERE `table_name` = '$param_2' AND `source` = '$param_1'";
    # Prepare the above MySQL query
    if ( my $sth = $dbh->prepare($sql)) {
      # Execute the MySQL query
      if ( $sth->execute() ) {
        # Bind columns to their respective hash keys
        if ( $sth->bind_columns(\$difference, \$datetime) ) {
          # Fetch values for the hash data
          if ( $sth->fetch ) {
            $sth->finish();
            $data{difference} = $difference;
            $data{datetime} = $datetime;

            return %data;
          # End of fetch
          } else {
            log_message(" -> unable to fetch data \$difference, \$datetime", 3, "query_etl_process_signals");
          }
        # End of bind columns to hash keys
        } else {
          log_message (" -> unable to bind columns \$difference, \$datetime", 3, "query_etl_process_signals");
        }
      # End of execution of MySQL Query
      } else {
        log_message (" -> unable to execute query: \"$sql\"", 3, "query_etl_process_signals");
        return;
      }
    # End Prepare query statement
    } else {
      log_message (" -> unable to prepare query: \"$sql\"", 3, "query_etl_process_signals");
    }
  } else {
    log_message ( "-> unable to query etl process signals: dbh file handle is not set", 3, "query_etl_process_signals" );
  }
}

sub query_cluster {
  my $dbh = shift;
  my $table = shift;
  my @data;


  if ( defined $dbh ) {
    my $sql = "SELECT max(`UTC_DateTime`), max(`DateTime`) FROM `" . $table . "`";

    if (my $sth = $dbh->prepare($sql)) {
      if ($sth->execute()) {
        my ($unix_time, $datetime);
        if ($sth->bind_columns(\$unix_time, \$datetime)) {
          if ($sth->fetch) {
              $sth->finish();

              push @data, $unix_time;
              push @data, $datetime;

              return @data;
          } else {
            log_message (" -> unable to fetch data for \$unix_time, \$datetime\n\t[System Msg] -> $DBI::errstr");
          }
        } else {
          log_message (" -> unable to bind columns \$unix_time, \$datetime\n\t[System Msg] -> $DBI::errstr");
        }
      } else {
        log_message (" -> unable to execute query: \"$sql\"\n\t[System Msg] -> $DBI::errstr", 3, "query_cluster");
      }
    } else {
      log_message (" -> unable to prepare query: \" $sql\"\n\t[System Msg] -> $DBI::errstr", 3, "query_cluster");
    }
  } else {
    log_message ( "-> unable to query cluster: dbh file handle not set", 3, "query_cluster" );
  }
}

sub query_hds {
  my $dbh = shift;
  my $table = shift;
  my @data;

  if ( defined $dbh ) {
    $table = 'Call_Type_SG_Half_Hour' if $table eq 'Call_Type_Skill_Group_Half_Hour';
    $table = 'Call_Type_SG_Interval' if $table eq 'Call_Type_Skill_Group_Interval';

    my $sql = "SELECT convert(varchar, max(DateTime), 20) FROM $table";
    if ( my $sth = $dbh->prepare( $sql ) ) {
      if ( $sth->execute() ) {
        my $datetime;
        if ( $sth->bind_columns( \$datetime ) ) {
          if ($sth->fetch) {
            push @data, str2time($datetime);
            push @data, $datetime;
            $sth->finish();

            return @data if @data;
          } else {
            log_message(" -> unable to fetch data from the HDS\n\t[System Msg] -> $DBI::errstr", 3, "query_hds");
          }
        } else {
          log_message(" -> unable to bind columns \$datetime\n\t[System Msg] -> $DBI::errstr", 3, "query_hds");
        }
      } else {
        log_message (" -> unable to execute query: \"$sql\"\n\t[System Msg] -> $DBI::errstr", 3, "query_hds");
      }
    } else {
      log_message (" -> unable to prepare query: \"$sql\"\n\t[System Msg] -> $DBI::errstr", 3, "query_hds");
    }
  } else {
    log_message ( " -> unable to find dbh file hanld\n\t[System Msg] -> $DBI::errstr", 3, "query_hds" );
  }
}

sub check_for_lock_file {
  my $lock_name = shift;
  my $type = shift;

  my $location = '/home/sextant-support/';
  my $file = $lock_name . '.lock';
  my $filepath = $location . $file;

  if( -f $filepath ) {
    log_message( "[$hostname][Lock] Lock file exists -> Setting status to FAIL since it has already alarmed before", 2, $type );
    return 'FAIL';
  } else {
    create_lock_file( $filepath, $type ) if $cron_run;
    log_message( "[$hostname][Lock] Setting status to UNKNOWN", 1, $type ) if !$cron_run;
    return 'UNKNOWN';
  }
}

sub check_and_clean_lockfile {
  my $lock_name = shift;
  my $type = shift;

  my $location = "/home/sextant-support/";
  my $file = $lock_name . ".lock";
  my $filepath = $location . $file;

  if(-f $filepath) {
    remove_lock_file( $filepath, $type ) if $cron_run;
  }
}

sub remove_lock_file {
  my $filepath = shift;
  my $type = shift;

  if(unlink $filepath) {
    log_message("[$hostname][Lock] $filepath removed", 1, $type);
  } else {
    log_message("[$hostname][Lock] Unable to remove $filepath file", 3, "Error");
  }
}

sub create_lock_file {
  my $filepath = shift;
  my $type = shift;

  open my $fh, '>>', $filepath or log_message("[$hostname][Lock] Unable to open lock file", 2, $type);

  if($fh) {
    log_message("[$hostname][Lock] Lock file created -> $filepath", 1, $type);
    print $fh '[' . localtime(time()) . '] ' . 'Initial creation of lock file.' . "\n";
  } else {
    log_message("[$hostname][Lock] Issues encountered with lock file creation", 3, "Error");
  }
}

sub write_lockfile {
  my $lock_file = shift;
  my $text = shift;

  my $message = "[" . localtime ( time ( ) ) . "] " . $text . "\n";

  open ( my $fh, '>>', $lock_file );
  print $fh $message;
  close $fh;

}

sub CCS_Trap_Check {
  $hostname = shift;
  $group = shift;
  $CCS_trap_contents = shift;

  my $send_update;

  if ( $CCS_trap_contents =~ m/FAIL/io || $CCS_trap_contents eq "" ) {
    if ( -e $lock_file ) {
      # If lock file already exists we're going CRITICAL
      if ( &write_lockfile ( $lock_file, "----> Update Trap for Critical Alarm\n\n$CCS_trap_contents\n" ) ) {
        log_message ( "[$hostname][$group] Sending critical message to CCS since lock file already exists", 5 );
      } else { log_message ( "[$hostname][$group] Unable to modify lock file for critical alarm", 5 ) }

      # Send CCS update
       `(/bin/echo "\nNode: Health:$hostname:$group:critical"; /bin/echo -e "$CCS_trap_contents") | /var/www/CaseSentry/bin/sendTrapCS.pl $trap_host $trap_string`;
        log_message ( "[$hostname][$group] Sending critical update to CCS", 5 );
        log_message ( "[$hostname][$group] Sending Health:$hostname:$group:critical to CCS\n$CCS_trap_contents", 5 );
    } else {
      # If the lock file is not present, warn and create one
        &write_lockfile ( $lock_file, "----> Initial creation\n\n$CCS_trap_contents\n" );
      # Send Warning to CCS
        `(/bin/echo "\nNode: Health:$hostname:$group:warning"; /bin/echo -e "$CCS_trap_contents") | /var/www/CaseSentry/bin/sendTrapCS.pl $trap_host $trap_string`;
        log_message ( "[$hostname][$group] Sending warning update to CCS\n$CCS_trap_contents\n", 5 );
        log_message ( "[$hostname][$group] Lock file created -> $lock_file", 5 );
    }
  } elsif ( $CCS_trap_contents =~ m/(PASS|UNKNOWN)/io ) {
    if ( -e $lock_file ) {
      # If the lock file exists, let's remove it since we passed
      if ( !unlink ( $lock_file ) ) { log_message ( "[$hostname][$group][error] Unable to remove $lock_file", 5 ); log_message ( "[$hostname][$group] Unable to remove lock file -> $lock_file", 3 ); }

      #Send Clear message to CCS
      `(/bin/echo "\nNode: Health:$hostname:$group:clear"; /bin/echo -e "$CCS_trap_contents") | /var/www/CaseSentry/bin/sendTrapCS.pl $trap_host $trap_string`;
        log_message ( "[$hostname][$group] Sending clear message to CCS for resolved alarm", 5 );
        log_message ( "[$hostname][$group] Detail: Node: Health:$hostname:$group:clear", 5 );
        log_message ( "[$hostname][$group] Lock file removed -> $lock_file\n$CCS_trap_contents", 5 );
    } else {
      # If we PASS and no lockfile exists, ignore since we don't need to send a clear message to a machine that's already in ground
    }
  }
}

sub log_message {
  my $message = shift;
  my $message_type = shift;
    # Message Type Key
    # 1 -> INFO
    # 2 -> WARNING
    # 3 -> ERROR
  my $message_detail = shift;

  if ( !defined $message_detail ) {
    $message_detail = 2;
  }

  # Set log file locations and names
  my $general_log     = $log_directory . "/health.log";
  my $error_log       = $log_directory . "/error.log";
  my $sendhealth_log  = $log_directory . "/sendhealth.log";
  my $fh;

  # Assign each messsage according to the message_type passed through
  $message = "[" . localtime ( time ( ) ) . "] [INFO] " . $message . "\n" if $message_type == 1 || $message_type == 2;
  $message = "[" . localtime ( time ( ) ) . "] [$message_detail]" . $message . "\n" if $message_type == 3;
  $message = "[" . localtime ( time ( ) ) . "]" . $message . "\n" if $message_type == 5;

  # Logic to determine which log file we need to write to
  if ( $message_type == 1 || $message_type == 2 ) {
    if ( open ( $fh, '>>', $general_log ) ) {
      print $fh $message;
    }
    close $fh;
  } elsif ( $message_type == 3 ) {
    if ( open ( $fh, '>>', $error_log ) ) {
      print $fh $message;
    }
    close $fh;
  } elsif ( $message_type == 5 ) {
    if ( open ( $fh, '>>', $sendhealth_log ) ) {
      print $fh $message;
    }
    close $fh;
  } else {
    if ( open ( $fh, '>>', $error_log ) ) {
      print $fh "Unable to determine which log to print to\n";
    }
    close $fh;
  }
}
