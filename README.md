# Jamf-API-Group-to-Search-Convertor

This script was made with the idea of trying to take a single or multiple smart groups and convert them into Advanced Searches. This edit will be able to: 

- Find a smart group by ID
- Take the Criteria of a Smart Group and make it work for creating an Advanced Search 
- Determine if an advanced search already exists with the same name

Honestly, I probably should just start learning swift as the constant Apple Script Prompts probably aren't the best workflow. 

V3 Update includes the logic to delete the smart groups after you completed the migration. (Only Successful Migrations will be given the option to delete.) 

Currently only able to be delete all or nothing. (No logic built to selectively choose which smart groups you want to delete)

LOGS!! There is now a log for the multiple migration path. Feel free to change the path, for now the script defaults to /tmp/conversion.log

This script was a lot of fun to build. Learned some really cool substitution strategies. No doubt there are more effiecent methods to this madness. 

## FYI

If you're looking for a solution that isn't using AppleScript to guide you through your journey, I would recommend checking out Mike Levenick's [Stupid Groups](https://github.com/mike-levenick/stupid-groups)
