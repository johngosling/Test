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
&do_it;
&send_to_va;
&disconnect;

sub do_it{
	$orgname=$form{'orgname'};
	$contactname=$form{'contactname'};
	$contacttel=$form{'contacttel'};
	$contactemail=$form{'contactemail'};
	$sector=$form{'sector'};
	$code=$form{'code'};
	$pwd=$form{'pwd'};
	
	$zorgname=dbq($orgname);
	$zcontactname=dbq($contactname);
	$zcontacttel=dbq($contacttel);
	$zcontactemail=dbq($email);
	$zsector=dbq($sector);
	$zcode=dbq($code);
	$zpwd=dbq($pwd);
	
	if ($form{'sectoradded'}==1){$sector=$form{'addorgsector'}; $zsector=dbq($sector);$sectoradded=1;}
	#-------------
	$sql="select count(id) from va_organisations where code=$zcode"; &runsql($sql);
	$i=0; while (@row=$sth->fetchrow_array) {$ncodes=$row[0];} &finishsql;
	if ($ncodes>0){print "0##This code already exists.  Please use a different code for the organisation"; return;}
	#-------------
	$sql="insert into va_organisations (`name`,contactname,contactemail,sector,contacttel,code,password) values ($zorgname,$zcontactname,$zcontactemail,$zsector,$zcontacttel,$zcode,$zpwd)"; runsql($sql); 
	$newid=$sth->{'mysql_insertid'}; finishsql();
	if ($sectoradded==1){$sql="insert into va_sectors (sector) values ($zsector)"; runsql($sql); finishsql();}
	print "1#$newid";
}
#-----------
# Send to VA
#-----------
sub send_to_va{
	#---------------
	# Construct json
	#---------------
	my @varnames=qw(orgid orgname contactname contacttel contactemail sector orgcode orgpassword sectoradded);
	my @values=($newid,$orgname, $contactname, $contacttel, $contactemail, $sector, $code, $pwd, $sectoradded);	
	if ($form{'sectoradded'}==1){push @varnames, 'sectoradded';push @values, $sectoradded;}
	for ($i=0;$i<=$#varnames;$i++){$data{$varnames[$i]}=$values[$i];}
	$json.=to_json(\%data);
	#debug($json); return;
	#-----------
	# Send to va
	#-----------
	$url='http://www.globiflow.com/catch/7r552ibd97vzd98';
	#$url='http://www.profilingforsuccess.com/cgi-bin/va_receive_json_test.pl';
	($result,$x)=make_http_request($url,$json);
	if ($result==0)	{send_error_email($x,$newid,$orgname,$contactname,$contacttel,$contactemail,$sector,$code,$pwd,$newsector,$json);} 
	else 			{$sql="update va_organisations set transmitted=1 where id=$newid"; &runsql($sql); &finishsql;}
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
	my ($x,$newid,$orgname,$contactname,$contacttel,$contactemail,$sector,$code,$pwd,$newsector,$json)=@_;
	$nl="\n";
	$fromaddress='profiling@profilingforsuccess.com';
	$toaddress='johngosling@profilingforsuccess.com';
	$subj="VA Organisation Registration: send status error: $x";
	$msg="Error string=$x".$nl;
	$msg.="OrgID=$newid".$nl;
	$msg.="Org name = $orgname".$nl;
	$msg.="Contact name = $contactname".$nl;
	$msg.="Contact tel = $contacttel".$nl;
	$msg.="Contactemail = $contactemail".$nl;
	$msg.="Code = $code".$nl;
	$msg.="Sector = $sector".$nl;
	$msg.="Pwd = $Pwd".$nl;
	$msg.="New sector = $newsector".$nl;
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