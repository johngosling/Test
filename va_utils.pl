 
sub va_do_matching(){
	my $scoresref=shift;
	my ($i,$napps,$matchlist,$matchscore,@apprids);
	#----------------------------------------------
	#  Get ids and profiles for all apprenticeships
	#----------------------------------------------
	$sql="select id,profile,themerankscores from va_apprenticeships where (profile is not null) and (themerankscores is not null)"; &runsql($sql);
	$i=0; while (@row=$sth->fetchrow_array) {$i++;$apprids[$i]=$row[0];$profiles[$i]=$row[1];$themerankscores[$i]=$row[2];} &finishsql;
	$napps=$i;
	#--------------------------------------------
	# Match the students scores with all profiles
	#--------------------------------------------
	for ($i=1;$i<=$napps;$i++){
		$matchscore=va_match($apprids[$i],$profiles[$i],$themerankscores[$i],$scoresref);
		$matchlist.=$apprids[$i].','.$matchscore.';';
	}
	return $matchlist;
}

sub va_match{
	#--------------------------------------
	# May need also to record students ipsative scores in order to use the theme rank scores !
	# Max profile score is 36.
	#--------------------------------------
	my ($profilescores,@themeranks,$i,$matchscore,$maxdiff);
	my ($apprid,$profile,$themeranks,$scoresref)=@_;
	my @scores=@$scoresref;
	@profilescores=split(/,/,$profile); unshift @profilescores,0;
	@themeranks=split(/,/,$themeranks); unshift @themeranks,0;
	#------------------------------
	#@scores=(0,1,2,3,5,5,6);  				# tmp !!!!!!!!!
	#@profilescores=(0,6,12,18,24,30,36); 	# tmp !!!!!!!!!
	#------------------------------
	#--------------------------------------------------
	# Basic method - problem is range of student scores
	#--------------------------------------------------
	#$maxdiff=9;
	#for ($i=1;$i<=6;$i++){
	#	$profilescores[$i] *= 10/36; # Transform to 1-10 scale
	#	$matchscore+=($maxdiff+1)-abs($profilescores[$i]-$scores[$i]);
	#}
	#----------------------------------------------
	#-----------------------------------------------
	# Adjusting student's scores for their max score
	#-----------------------------------------------
	# my (@adjscores,$max);
	#$maxdiff=9;
	#$max=0;
	#for ($i=1;$i<=6;$i++){if ($scores[$i]>$max){$max=$scores[$i];}}
	#for ($i=1;$i<=6;$i++){
	#	$profilescores[$i] *= 10/36; # Transform to 1-10 scale
	#	$adjscores[$i]=$scores[$i]*(10/$max);
	#	$matchscore+=($maxdiff+1)-abs($profilescores[$i]-$adjscores[$i]);
	#}
	#$matchscore*=100/60;  # To convert from max 60 to 100
	#-----------------------------------------------
	#-----------------------
	# Using rank scores only (problem is that values are constrained so minimum score 50 if order is the opposite)
	#-----------------------
	my (%scorehash,%profilehash,@sortedscores,@sortedprofilescores,@scoreranks,@profileranks);
	for ($i=1;$i<=6;$i++){
		$scorehash{$i} = $scores[$i];
		$profilehash{$i} = $profilescores[$i];
	}
	@sortedscores =        sort {$scorehash{$b} <=> $scorehash{$a}} keys %scorehash;
	@sortedprofilescores = sort {$profilehash{$b} <=> $profilehash{$a}} keys %profilehash;	
    for ($i=1;$i<=6;$i++){
    	$scoreranks[$sortedscores[$i-1]]=$i;
		$profilescoreranks[$sortedprofilescores[$i-1]]=$i;
    }	
	$maxdiff=5;
	for ($i=1;$i<=6;$i++){
		$matchscore+=($maxdiff+1)-abs($profilescoreranks[$i]-$scoreranks[$i]);
	}
	$matchscore*=100/36;  # To convert from max 36 to 100
	#----------------------------------------
	$matchscore=int($matchscore-0.5);
	return $matchscore;
}

sub va_send_matchlist_to_va{
	#Matchlist format: jobid,matchscore; jobid,matchscore;

	my (@tmp1,@tmp2,$json,$result,$x);
	my ($vastudentid,$matchlist,$scoresref)=@_;
	my @scores=@$scoresref;
	#---------------
	# Construct json
	#---------------
	$nl="\n";
	$json.='{'.$nl;																#  {
	$json.='"studentid":"'.$vastudentid.'",'.$nl;								#  "studentid":"2345",
	for ($i=1;$i<=6;$i++){$json.='"ciiscore'.$i.'":"'.$scores[$i].'",'.$nl;}	#  "ciiscore1":"5",
	$json.='"matches":['.$nl;													#  "matches":[
	@tmp1=split(/;/,$matchlist);  
	foreach my $t (@tmp1){
		@tmp2=split(/,/,$t);
		$json.='{"apprenticeshipid":"'.$tmp2[0].'","matchscore":"'.$tmp2[1].'"},'.$nl; # {"appraisalid":"1","matchscore":"8"},
	}
	$json=substr($json,0,-2);  # Remove last $nl and comma
	$json.=$nl."]";																#  ]
	$json.='}'.$nl;  															#  }
	debug($json);
	#-----------
	# Send to va
	#-----------
	#$url='http://www.globiflow.com/catch/134d15000bi363k'; 
	$url='http://www.profilingforsuccess.com/cgi-bin/va_receive_json_test.pl';
	$zzz=1;
	($result,$x)=make_http_request_json($url,$json);
	if ($result==0)	{send_va_error_email($x,$studentid,$firstname,$lastname,$json);} 
	else 			{$sql="update va_students set urltransmitted=1 where id=$newid"; &runsql($sql); &finishsql;}

}
sub make_http_request_json{
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
sub va_send_error_email{
	my ($fromaddress,$toaddress,$subject,$msg,$replyto,$returnpath);
	my ($x,$studentid,$firstname,$lastname,$json)=@_;
	$nl="\n";
	$fromaddress='profiling@profilingforsuccess.com';
	$toaddress='johngosling@profilingforsuccess.com';
	$subj="VA Student Matching Transmission: send status error: $x";
	$msg="Error string=$x".$nl;
	$msg.="Student ID=$studentid".$nl;
	$msg.="Firstname=$firstname".$nl;
	$msg.="Lastname = $lastname".$nl;
	$msg.="JSON:".$nl;
	$msg.=$json.$nl;
	$replyto=$fromaddress;$returnpath=$fromaddress;
	send_message($toaddress,$fromaddress,$replyto,$returnpath,$subj,$msg,6);
}

#------
# Debug
#------
sub debug{
	my $txt=shift;
	my $fname=$cgipath.'debug.txt';
	my $x="  "; my $nl="\n\n";
	if (open (CFILE, ">".$fname)){
		print CFILE $txt;
		close (CFILE);
	}
}



1;