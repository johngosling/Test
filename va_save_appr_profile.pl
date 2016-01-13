#!/usr/bin/perl
 
print "Content-Type:text/html\n\n";

use JSON;
use LWP::UserAgent;
use Crypt::SSLeay; 
use MIME::Lite;
use Net::SMTP;
use DBI;
use Cwd 'abs_path'; setpath();

require "mysqllib.pl";
require "commadminutils.pl";

&where_am_i("commercial");
&parse_form;
&connect_to_db;
&save_data;
&do_profile;
&send_to_va;
&disconnect;



sub save_data{
	$apprid=$form{'apprid'};
	$profiledata=$form{'profiledata'};
	$themerankscores=$form{'themerankscores'};
	$zprofiledata=dbq($profiledata);
	$zthemerankscores=dbq($themerankscores);
	$sql="update va_apprenticeships set profiledata=$zprofiledata,themerankscores=$zthemerankscores where id=$apprid"; runsql($sql); finishsql();
	if ((length($form{'apprtitle'})>0)and(length($form{'apprdescription'}) >0)){
		$dotitle=1;
		$title=$form{'apprtitle'};
		$description=$form{'apprdescription'};
		$ztitle=dbq($title);
		$zdescription=dbq($description);
		$sql="update va_apprenticeships set title=$ztitle,description=$zdescription where id=$apprid"; runsql($sql); finishsql();
	}
	print "1#";
}

sub do_profile{
	my @tmp=split(/,/, $profiledata);
	$nthemes=6;$itemspertheme=6;$cnt=-1;
	for ($i=1;$i<=$nthemes;$i++){
		for ($j=1;$j<=$itemspertheme;$j++){$cnt++; $scores[$i]+=$tmp[$cnt];}
		$profile.=$scores[$i].',';
	}
	$zprofile=dbq($profile);
	$sql="update va_apprenticeships set profile=$zprofile where id=$apprid"; runsql($sql); finishsql();
}
#-----------
# Send to VA
#-----------
sub send_to_va{
	#---------------
	# Construct json
	#---------------
	my @varnames=qw(apprid themescore1 themescore2 themescore3 themescore4 themescore5 themescore6);
	my @values=($apprid, $scores[1], $scores[2], $scores[3], $scores[4], $scores[5], $scores[6]);	
	if ($dotitle==1){push @varnames,'title'; push @varnames,'description'; push @values,$title; push @values,$description;}
	for ($i=0;$i<=$#varnames;$i++){$data{$varnames[$i]}=$values[$i];}
	$json.=to_json(\%data);
	#debug($json); return;
	#-----------
	# Send to va
	#-----------
	$url='http://www.globiflow.com/catch/bl3v1y97h977wur';
	#$url='http://www.profilingforsuccess.com/cgi-bin/va_receive_json_test.pl';
	($result,$x)=make_http_request($url,$json);
	if ($result==0)	{send_error_email($x,$apprid,$json);} 
	else 			{$sql="update va_organisations set datatransmitted=1 where id=$newid"; &runsql($sql); &finishsql;}
}

#-----------------------
# HTTP Request functions
#-----------------------
sub make_http_request{
	my ($cgiquery,$user_agent,$request,$result);
	my ($data,$nvars,@pairs,$pair,$key,$value,%vars);
	my ($url,$json)=@_; 
	$user_agent=new LWP::UserAgent;
	$request=new HTTP::Request("POST", $url);
	$request->content_type("application/json"); # http://stackoverflow.com/questions/4199266/how-can-i-make-a-json-post-request-with-lwp
	$request->content($json);
	$result=$user_agent->request($request);
	if ($result->is_error)    {return (0, "Error code: ".$result->status_line);}
	if ($result->is_info)     {return (0, "Informational code: ".$result->status_line);}
	if ($result->is_redirect) {return (0, "Redirection code: ".$result->status_line);}
	if ($result->is_success)  {return (1, "Success");} # n.b. In some circumstances, a redirection may occur via OS so still produce useful result
}
sub send_error_email{
	my ($fromaddress,$toaddress,$subject,$msg,$replyto,$returnpath);
	my ($x,$apprid,$json)=@_;
	$nl="\n";
	$fromaddress='profiling@profilingforsuccess.com';
	$toaddress='johngosling@profilingforsuccess.com';
	$subj="VA Save Apprenticeship Profile: send status error: $x";
	$msg="Error string=$x".$nl;
	$msg.="ApprenticeshipID=$apprid".$nl;
	$msg.="JSON:".$nl;
	$msg.=$json.$nl;
	$replyto=$fromaddress;$returnpath=$fromaddress;
	send_message($toaddress,$fromaddress,$replyto,$returnpath,$subj,$msg,6);
}
#-----------------
# E-MAIL FUNCTIONS
#-----------------
sub send_message{
	my($toaddress,$fromaddress,$replyto,$returnpath,$subject,$message,$numb)=@_;
	$msg = MIME::Lite->new(
		From		=>$fromaddress,
		To			=>$toaddress,
		Subject		=>$subject,
        Reply-To	=>$replyto,
        Return-Path	=>$returnpath,
		Data		=>$message
	);
	$msg->attr('content-type.charset' => 'UTF-8'); 
	if (($testing!=1) and (length($toaddress)>0)){&send_netsmpt_msg($fromaddress,$toaddress,$subject,$msg);} ### Net:SMTP
	if ($testing==1){&tmp_save_mimelite($msg,$numb);}
}
sub send_netsmpt_msg{
	my ($fromaddress,$recipientaddress,$subj,$msg)=@_;
	my $msgbody = $msg->as_string();
	my $servername = "smtpcorp.com";  
	my $username='linda.paxton@teamfocus.co.uk'; 
	my $password='TeamFocus'; 
	$smtp=Net::SMTP->new($servername, Port => 2525, Timeout => 30);
	#---------------
	$nosmtp=0;$authfailed=0;
	if (not $smtp){$nosmtp=1;}
	elsif (not $smtp->auth($username, $password)){$authfailed=1;}
	if (($nosmtp==1)or($authfailed==1)){$msg->send;}
	else {
		$smtp->mail($fromaddress);
		$smtp->to($recipientaddress);
		$smtp->data(); 
		$smtp->datasend($msgbody); 
		$smtp->dataend(); 
		$smtp->quit();
	} 
}
sub tmp_save_mimelite{
	my ($msg,$numb)=@_;
	my ($fname,$z,$n,$desktop);
	$desktop="c:/Users/Admin/desktop/";
	if ($mylocalhost==1){
		#-------------------------------------------------------------------------------------------------
		# for running from my local host
		# Need to enable sharing of the email folder
		# i.e. Properties/Sharing/Share this folder on the network + allow other users to change my files
		#-------------------------------------------------------------------------------------------------
		$z="Cand"; if ($numb==2){$z="Client";}
		&get_date;
		$n="$fullname $z $msgtime";
		$fname=$desktop."PFS/PFS emails/$n".".eml";
		if ($numb>2){$fname=$desktop."PFS/PFS emails/email".$numb.".eml";}
	} else {
		$fname=$desktop."email".$numb.".eml";
	}
	open (CFILE, ">".$fname);
	$msg->print(\*CFILE);
	close (CFILE); 
}

#---------
# sql Die nice
#---------
sub sqldienice {
	my $sql = shift;
	my $x = DBI->errstr;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time); 
	my $yr=$year + 1900;$mon ++;
	if (open (CFILE, ">>sqlerrors.log")){
		print CFILE "$mday/$mon/$yr  $hour:$min:$sec  IP=$ENV{'REMOTE_ADDR'}\nScript=$ENV{'SCRIPT_NAME'}  QueryString:$ENV{'QUERY_STRING'}\nSQL: $sql\n$x\n\n";
		close (CFILE);
	}
	if ($sqlrun==1)   {$rc = $sth->finish;}
	if ($dbopened==1) {$rc = $db->disconnect();}
	exit;
}
#---------
# Die nice
#---------
sub dienice {
	exit;
}
sub setpath{
	my ($path,@tmp,$del,$fname);
	$path=abs_path($0); $del='/';@tmp=split(/$del/,$path); $fname=pop(@tmp); #print "<p>$fname";
	$path =~ s/$fname//gi; 	#print "<p>$path";
	chdir($path);
}