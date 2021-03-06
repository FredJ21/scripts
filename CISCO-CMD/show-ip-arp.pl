#! /usr/bin/perl 
# ============================================================================
#		CISCO SNMP SHOW IP ARP
#							Frederic JELMONI
#							Mars 2016
#	
#	Ref :
#		http://snmp.cloudapps.cisco.com/Support/SNMP/do/BrowseOID.do
#		http://www.cisco.com/c/en/us/support/docs/ip/simple-network-management-protocol-snmp/44800-mactoport44800.html	
#		http://cpansearch.perl.org/src/DTOWN/Net-SNMP-5.2.0/examples/snmpwalk.pl
#
# ============================================================================
use Net::SNMP v5.1.0 qw(:snmp DEBUG_ALL);
use Getopt::Std;

use strict;
use vars qw(%OPTS);

autoflush STDOUT 1;

# Validate the command line options
if (!getopts('a:A:c:dD:E:m:n:p:r:t:u:v:x:X:', \%OPTS)) {	_usage();}

# Do we have enough/too much information?
if (@ARGV != 1) {	_usage();	}

my $host = $ARGV[0];

my $s;		# SNMP session
my $e;		# SNMP error
my $community;
my @RESULT;

# ============================================================================
#				MAIN
# ============================================================================

# ---------------------------------------------------------------------------
# 				Table VLAN / Int Index	

  my %interface;
  @RESULT ="";
  $community = $OPTS{c};
  _openSession();
  _get("1.3.6.1.2.1.2.2.1.2");

  foreach (@RESULT) {
	if(/1\.3\.6\.1\.2\.1\.2\.2\.1\.2\.(\d+) = OCTET STRING: (\w+)/) {
		my $INDEX = $1;
		my $IfDesc = $2;

		$IfDesc =~ s/vlan//;
		$IfDesc =~ s/Vlan//;
  	
		$interface{$INDEX} = $IfDesc;
	} 
  } 
  _closeSession();

# ---------------------------------------------------------------------------
# 				Table Int Index / IP / MAC	
#				Afficahge

  @RESULT ="";
  $community = $OPTS{c};
  _openSession();
  _get("1.3.6.1.2.1.3.1.1.2");

  print "\n\n\n";
  printf ("%10s %20s %20s %15s\n", "Index", "Vlan", "IP", "Mac");
  print  ("--------------------------------------------------------------------------\n");

  foreach (@RESULT) {
	if(/1\.3\.6\.1\.2\.1\.3\.1\.1\.2\.(\d+)\.1\.(\d+\.\d+\.\d+\.\d+) = OCTET STRING: 0x(\w\w\w\w\w\w\w\w\w\w\w\w)/) {
		my $INDEX = $1;
		my $IP   = $2;
		my $MAC  = $3;
  		
		printf ("%10s %20s %20s %15s\n", $INDEX, $interface{$INDEX}, $IP, $MAC);
	} else {
	
		#print "Error:".$_."\n";
	}
  } 
  _closeSession();

exit 0;


# [private] ------------------------------------------------------------------
sub _openSession
{

	($s, $e) = Net::SNMP->session(
	   -hostname => $host,
	   exists($OPTS{a}) ? (-authprotocol =>  $OPTS{a}) : (),
	   exists($OPTS{A}) ? (-authpassword =>  $OPTS{A}) : (),
	   -community    =>  $community,
	   exists($OPTS{D}) ? (-domain       =>  $OPTS{D}) : (),
	   exists($OPTS{d}) ? (-debug        => DEBUG_ALL) : (),
	   exists($OPTS{m}) ? (-maxmsgsize   =>  $OPTS{m}) : (),
	   exists($OPTS{p}) ? (-port         =>  $OPTS{p}) : (),
	   exists($OPTS{r}) ? (-retries      =>  $OPTS{r}) : (),
	   exists($OPTS{t}) ? (-timeout      =>  $OPTS{t}) : (),
	   exists($OPTS{u}) ? (-username     =>  $OPTS{u}) : (),
	   exists($OPTS{v}) ? (-version      =>  $OPTS{v}) : ( -version      =>  '2c'),	
	   exists($OPTS{x}) ? (-privprotocol =>  $OPTS{x}) : (),
	   exists($OPTS{X}) ? (-privpassword =>  $OPTS{X}) : ()
	);

	# Was the session created?
	if (!defined($s)) {
  		 _exit($e);
	}
}
sub _closeSession
{
	# Close the session
	$s->close();
}
sub _get 
{
	my ($OID) = (@_);

	my @args = (
	   exists($OPTS{E}) ? (-contextengineid => $OPTS{E}) : (),
	   exists($OPTS{n}) ? (-contextname     => $OPTS{n}) : (),
	   -varbindlist    => [$OID]
	);
	
	if ($s->version == SNMP_VERSION_1) {

	   my $oid;
	
	   while (defined($s->get_next_request(@args))) {
	      $oid = ($s->var_bind_names())[0];
	
	      if (!oid_base_match($OID, $oid)) { last; }
	      push(@RESULT, $oid .' = '. snmp_type_ntop($s->var_bind_types()->{$oid}) .': '. $s->var_bind_list()->{$oid} );
	
	      @args = (-varbindlist => [$oid]);

	      print ".";
	   }
	
	} else {
	
	   push(@args, -maxrepetitions => 25); 
	
	   outer: while (defined($s->get_bulk_request(@args))) {
	
	      my @oids = oid_lex_sort(keys(%{$s->var_bind_list()}));
	
	      foreach (@oids) {
	
	         if (!oid_base_match($OID, $_)) { last outer; }
	      	 push(@RESULT, $_ .' = '. snmp_type_ntop($s->var_bind_types()->{$_}) .': '. $s->var_bind_list()->{$_} );

	         # Make sure we have not hit the end of the MIB
	         if ($s->var_bind_list()->{$_} eq 'endOfMibView') { last outer; } 
	   
		print ".";
	      }
	
	      # Get the last OBJECT IDENTIFIER in the returned list
	      @args = (-maxrepetitions => 25, -varbindlist => [pop(@oids)]);
	   }
	
	}

	# Let the user know about any errors
	if ($s->error() ne '') {
	   _exit($s->error());
	}
}
sub _printTab
{
	#foreach (@_) {	print '['. $_ ."]\n"; }	
	foreach (@_) {	print  $_ ."\n"; }	
}
sub _exit
{
   	printf join('', sprintf("%s: ", $0), shift(@_), ".\n"), @_;
   	exit 1;
}

sub _usage
{
   print << "USAGE";

Usage: $0 [options] <hostname> 
Options: -v 1|2c|3      SNMP version
         -d             Enable debugging
   SNMPv1/SNMPv2c:
         -c <community> Community name
   SNMPv3:
         -u <username>  Username (required)
         -E <engineid>  Context Engine ID
         -n <name>      Context Name
         -a <authproto> Authentication protocol <md5|sha>
         -A <password>  Authentication password
         -x <privproto> Privacy protocol <des|3des|aes>
         -X <password>  Privacy password
   Transport Layer:
         -D <domain>    Domain <udp|udp6|tcp|tcp6>
         -m <octets>    Maximum message size
         -p <port>      Destination port
         -r <attempts>  Number of retries
         -t <secs>      Timeout period

USAGE
   exit 1;
}

# ============================================================================

