#!/bin/bash

################## Computer Smart Group to Advanced Search ###################
##############################################################################
# A script to convert smart groups to Advanced Searches                      #
# This script was created by Chris Zimmerman on December 13th 2022  
# V3 created on 3/2/2023
#                                                                            #
# By using this script you accept to use it "as-is".                         #
#                                                                            #
#                                                                            #
##############################################################################
#API USER
user=""
#API PASSWORD
pass=""
# URL (https://yourjamfserver.jamfcloud.com)
jurl=""

############# CHECK TO MAKE SURE ALL FIELDS ARE FILLED OUT ###################
############# IF NOT USER WILL BE PROMPTED TO DO SO ##########################
#Prompt for URL for Jamf Pro Server (https://yourjamfproserver.jamfcloud.com)

if [[  -z $jurl ]]; then
	
	jurl=$(osascript << EOF
set jurl to display dialog "Jamf Pro Server URL (https://yourjamf.jamfcloud.com):" default answer "" buttons {"Continue"} default button "Continue"
text returned of jurl
EOF
)
	
fi

#Prompt for API Username
if [[  -z $user ]]; then
	
	user=$(osascript << EOF
set user to display dialog "Enter API Username:" default answer "" buttons {"Continue"} default button "Continue"
text returned of user
EOF
)
	
fi

#Prompt for API Password
if [[  -z $pass ]]; then
	
	pass=$(osascript << EOF
set pass to display dialog "Enter API password:" default answer "" buttons {"Continue"} default button "Continue" with hidden answer
text returned of pass
EOF
)
	
fi
################## END CREDENTIAL CHECK #######################################
## Log File
logfile=/tmp/conversionlog.txt
quickcsv=/tmp/deletequeue.csv
date=$(date)

if [[ ! -e $logfile ]]; then
	echo "no log file found, creating now"
	touch $logfile
else
	echo "log file exists, prompting user"
	logremoval=$(osascript << EOF
set theDialogText to "Log File Found!

Recommended action is to delete old logs, however, if you would like to continue with the same log file please click 'Keep'"
display dialog theDialogText buttons {"Keep", "Delete"} default button "Delete"
EOF
)
	if [[ $logremoval =~ "Delete"  ]]; then
		echo "creating a new log file"
		rm $logfile
		touch $logfile
	else
		echo "going to append results"
	fi
fi
################## BEARER TOKEN RETRIEVAL #####################################
#Start of getting Bearer Token
classicCredentials=$(printf "${user}:${pass}" | /usr/bin/iconv -t ISO-8859-1 | /usr/bin/base64 -i - )

# generate an auth token
authToken=$( /usr/bin/curl "${jurl}/uapi/auth/tokens" \
--silent \
--request POST \
--header "Authorization: Basic ${classicCredentials}" )

#bearertoken
token=$( /usr/bin/awk -F \" '{ print $4 }' <<< "$authToken" | /usr/bin/xargs )
################## END BEARER TOKEN ###########################################

################### CREATE XSLT Stylesheet ####################################
######################################################
### XSLT Document that will parse through          ###
### any unnecessary information that will be used  ###
### for the creation of the Advanced Search        ###
######################################################

cat << EOF > /tmp/stylesheet.xslt
<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="xml"/>
	<xsl:template match="node()|@*">
	<xsl:copy>
		<xsl:apply-templates select="node()|@*"/>
	</xsl:copy>
	</xsl:template>
<xsl:template match="computers"/>
</xsl:stylesheet>
EOF

################## END OF XSLT DOC ###########################################

################ BEGIN WORKFLOW ##############################################
# Prompt for Document or Single ID

howto=$(osascript << EOF
set theDialogText to "Are you wanting to migrate one or multiple smart groups?"
display dialog theDialogText buttons {"One", "Multiple", "Cancel"}
EOF
)
echo $howto

document=0
solo=0
## Checks response to determine workflow ###

if [[ $howto =~ Multiple ]]; then
	((document++))
elif [[ $howto =~ One ]]; then
	((solo++))
else
	echo "Project Cancelled"
	exit 2
fi

#################### Document / Multiple workflow ################################	
if [[ $document -gt 0 ]]; then
	#### Validate the file exists and is a csv file ####
	valid=0
	
	while [[ $valid -ne 3 ]]; do
		file=$(osascript << EOF
set theResponse to display dialog "Provide a valid file path to a .csv file" default answer "" buttons {"Cancel", "Continue"} default button "Continue"
text returned of theResponse
EOF
)
		echo "Validating file $file"
		#check if file exists
		if [[ -f "$file" ]]; then
			echo "file is here"
			((valid++))
			((valid++))
		else
			echo "oh no!"
		fi
		
		#checks to see if the file extension is .csv
		if [[ "$file" =~ .csv$ ]]; then
			echo "this is a csv"
			((valid++))
		else
			echo "this is not a csv"
		fi
		
		echo "valid is $valid"
		#errors 
		
		if [[ $valid -eq 0  ]]; then
			novalid=$(osascript << EOF
set theDialogText to "The file $file does not exist and is not a csv file"
display dialog theDialogText buttons {"Retry"}
EOF
)
			echo "resetting valid"
		elif [[ $valid -eq 2 ]]; then
			notcsv=$(osascript << EOF
set theDialogText to "The file $file is not a csv file"
display dialog theDialogText buttons {"Retry"}
EOF
)
			echo "resetting valid"
			valid=0
		elif [[ $valid -eq 1 ]]; then
			notfilepath=$(osascript << EOF
set theDialogText to "The file $file does not exist"
display dialog theDialogText buttons {"Retry"}
EOF
)
			echo "resetting valid"
			valid=0
		fi
		echo "valid is $valid"
	done
	
	echo "$file is a valid file and is a csv file"
#################### File Validation Complete ###############################
#################### Convert Smart Groups to Advanced Searches ##############	
	cleanup=0
	err=0
	mirror=0
	static=0
	while IFS=, read -r id; do
		# Format info from the XSLT and make it acceptable for the request 
		echo "checking smart group id=$id"
		prexml=$(curl -s $jurl/JSSResource/computergroups/id/$id -X GET -H "accept: text/xml" -H "Authorization: Bearer $token")
		name=$( echo "$prexml" | xmllint --xpath "/computer_group/name/text()" -)
		
		if [[ $prexml != *criterion* ]]; then
			echo "$name (id=$id) is not a smart group"
			stag+=("$id, $name")
			((static++))
		else
			#makes sure the name is searchable in a curl command (replaces spaces)
			convertname=$(echo $name | sed "s/ /%20/g")
			#Checks to see if Advanced Search Already has one with the same name
			checkfordupes=$(curl -s $jurl/JSSResource/advancedcomputersearches/name/$convertname -X GET -H "accept: text/xml" -H "Authorization: Bearer $token")
			if [[ $checkfordupes == *"html"* ]]; then
				# Converts raw XML data into something usable for post command
				xml=$(echo $prexml| xsltproc /tmp/stylesheet.xslt - | awk 'NR>1' | sed "s/computer_group/advanced_computer_search/g")
				# Takes the formatted XML information and creates the advanced search
				post=$(curl -s $jurl/JSSResource/advancedcomputersearches/id/0 -H "content-type: text/xml" -H "Authorization: Bearer $token" -d "$xml")
				if [[ $post == *"html"* ]]; then
					echo "There was an error converting $name (id=$id)"
					error+=("$id, $name")
					((err++))
				else
					echo "$name (id=$id) was converted into an advanced search successfully"
					successful+=("$id, $name")
					((cleanup++))
				fi
			else
				echo "There is already an advanced search with the name '$name'"
				dupes+=("$id, $name")
				((mirror++))
			fi
		fi
		
	done < $file
	
#format results for the log file / deletion prompt 
	groupsthatdupe=$(printf '%s\n' "${dupes[@]}")
	groupsthaterr=$(printf '%s\n' "${error[@]}")
	groupsthatstat=$(printf '%s\n' "${stag[@]}")
	groupsthatrule=$(printf '%s\n' "${successful[@]}")
	
	##### Logging Away ####
	echo "Conversation report on $date" >> $logfile
	echo "" >> $logfile
	echo "Success: $cleanup, Errors: $err, Duplicates: $mirror, Static: $static" >> $logfile
	echo "" >> $logfile
	echo "The following groups have advanced searches with the same name:
$groupsthatdupe"  >> $logfile
	echo "" >> $logfile
	echo  "The Following Ids / Groups resulted in an error: 
$groupsthaterr" >> $logfile
	echo "" >> $logfile
	echo "The Following Ids / Groups are Static: 
$groupsthatstat" >> $logfile
	echo "" >> $logfile
	echo "The Following Ids / Groups were successful:
$groupsthatrule" >> $logfile
	echo "" >> $logfile

echo "$groupsthatrule" > $quickcsv
## Quick Report of groups that 
	osascript << EOF
set theDialogText to "Breakdown of Conversion

Success= $cleanup smart groups converted
Error= $err smart groups could not be converted
Dupes= $mirror number of advanced searches with the same name exist
Static= $static number of groups that were actually static

For a detailed breakdown, check the log ($logfile)"
display dialog theDialogText buttons {"Continue"} default button "Continue"
EOF
	## Deletion Workflow
deletegroups=$(osascript << EOF
set theDialogText to "You have successfully created an advanced search for the follwing:
$groupsthatrule

Would you like to delete these smart groups (This action is all or nothing)?"
display dialog theDialogText buttons {"Delete Smart Groups", "No thanks"}
EOF
)

	if [[ $deletegroups =~ "Delete Smart Groups" ]]; then
		massfinalwarning=$(osascript << EOF
set theDialogText to "WARNING: You are about to delete $cleanup smart groups: 

$groupsthatrule

Do you wish to proceed?"
display dialog theDialogText buttons {"Delete Smart Groups", "No thanks"}
EOF
)
	else
		echo "Not Deleting these groups after all"
		exit 0
	fi
	errdel=0
	succdel=0
	
	if [[ $massfinalwarning =~ "Delete Smart Groups" ]]; then
		while IFS=, read -r dtsg dsgn; do
			massdeletion+=($(curl -s $jurl/JSSResource/computergroups/id/$dtsg -X DELETE -H "Authorization: Bearer $token"))
			if [[ ${massdeletion[@]} =~ *dependent* ]]; then
				errordelete+=("$dtsg, $dsgn")
				((errdel++))
			else
				successdelete+=("$dtsg, $dsgn")
				((sucdel++))
			fi
		done < $quickcsv
	else
		echo "Deletion Process Cancelled"
	fi
	#removing document used in this while loop
	rm $quickcsv
	#### Deletion Completion Prompt ####
	osascript << EOF
set theDialogText to "Your request to mass delete smart groups:

Success(es): $sucdel
Failure(s): $errdel

For a comprehensive list, check the log ($log file)"
display dialog theDialogText buttons {"Continue"} default button "Continue"	
EOF

### Format variables ###
finaldelete=$(printf '%s\n' "${errordelete[@]}")
finalsuccess=$(printf '%s\n' "${successdelete[@]}")

### Deletion Logs ####
echo "DELETION LOGS" >> $logfile
echo "" >> $logfile
echo "The following smart groups were deleted:
$finalsuccess" >> $logfile
echo "" >> $logfile
echo "The following smart groups have a dependency and will need review in order to be deleted:
$finaldelete" >> $logfile
echo "" >> $logfile
fi
exit 0
########### END DOCUMENT WORK FLOW ########################################
	
################ Solo workflow ############################################
if [[ solo -gt 0 ]]; then
	id=$(osascript << EOF
set theResponse to display dialog "Enter the Smart Group ID: (Numbers Only)" default answer "" with icon note buttons {"Cancel", "Continue"} default button "Continue"
text returned of theResponse
EOF
)

	# Format info from the XSLT and make it acceptable for the request 
	prexml=$(curl -s $jurl/JSSResource/computergroups/id/$id -X GET -H "accept: text/xml" -H "Authorization: Bearer $token")
	name=$( echo "$prexml" | xmllint --xpath "/computer_group/name/text()" -)
	convertname=$(echo $name | sed "s/ /%20/g")
	checkfordupes=$(curl -s $jurl/JSSResource/advancedcomputersearches/name/$convertname -X GET -H "accept: text/xml" -H "Authorization: Bearer $token")
	
	if [[ $prexml != *criterion* ]];then 
	osascript << EOF
set theDialogText to "An error has occurred: $name with id=$id is not a valid smart group"
display dialog theDialogText buttons {"Cancel"}
EOF
		exit 1
	elif [[ $checkfordupes == *"html"*  ]]; then
		xml=$(echo $prexml| xsltproc /tmp/stylesheet.xslt - | awk 'NR>1' | sed "s/computer_group/advanced_computer_search/g")
		# Takes the formatted XML information and creates the advanced search 
		post=$(curl -s $jurl/JSSResource/advancedcomputersearches/id/0 -H "content-type: text/xml" -H "Authorization: Bearer $token" -d "$xml")
			if [[ $post == *"html"* ]]; then
			osascript << EOF
set theDialogText to "An error has occurred: the creation of the advanced search was unsuccessful"
display dialog theDialogText buttons {"Return"}
EOF
			exit 1 
		else
			#Successful Creation, Prompt for Deletion
			delete=$(osascript << EOF
set theDialogText to "You have successfully created an advanced search from $name (id=$id) Would you like to delete this smart group?"
display dialog theDialogText buttons {"Delete Smart Group", "No thanks"}
EOF
)
			fi
		else
			#Advanced Search May Already Exist
				osascript << EOF
set theDialogText to "An Advanced Search with the same name as $name already exists"
display dialog theDialogText buttons {"Return"}
EOF
	fi
fi

#Prompt for Deletion 
if [[ $delete =~ "Delete Smart Group" ]]; then
	finalwarning=$(osascript << EOF
set theDialogText to "WARNING: You are about to delete the smart group $name (id=$id) Do you wish to proceed?"
display dialog theDialogText buttons {"Delete Smart Group", "No thanks"}
EOF
)
else 
	exit 0
fi

#DELETION WORKFLOW
if [[ $finalwarning =~ "Delete Smart Group" ]]; then
	deletion=$(curl -s $jurl/JSSResource/computergroups/id/$id -X DELETE -H "Authorization: Bearer $token")
	if [[ $deletion == *dependent* ]]; then
		osascript << EOF
set theDialogText to "There was an issue with deleting smart group $name (id=$id). There are dependencies that are stopping the deletion. Please review and delete on your own."
display dialog theDialogText buttons {"Okay"}
EOF

	else
		osascript << EOF
set theDialogText to "Succesfully Deleted $name (id=$id). There are dependencies that are stopping the deletion. Please review and delete seperately."
display dialog theDialogText buttons {"Okay"}
EOF
	fi
else 
	exit 0
fi

exit 0
##################### END SOLO WORKFLOW ##################################
