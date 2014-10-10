<!---
	Author 	    :	Robert Rawlins (http://weboffins.com)
	Date        :	January 31st 2011
	Description :	The PostBox Service is used to send emails from your ColdBox applications, as a direct replacement to the stock 
					ColdBox MailService Plugin. Emails are sent through PostMarkApp.com API rather than over standard SMTP. 
					
	Requirements:	A PostMarkApp (http://postmarkapp.com/) Account & API Key.

	PostMarkApp	:	PostMarkApp (http://postmarkapp.com/) is a web service based email provider. Rather than sending emails 
					using standard SMTP protocols, you make a REST reuest to their API. Each mail is then assigned a message_id,
					you can then use their bounce back API's and webhooks to track mail delivery.
					
	Install		:	Simply replace references to the standard MailService in your application so they point at the PostBox
					plugin rather than the stock MailService plugin. You also need to add a custom setting to your ColdBox 
					configuration file which contains your PostMarkApp API key.
					
					e.g. 
					
					// custom settings
					settings = {
						// PostMarkApp Settings
						PostMarkApiKey = "your-api-key-goes-here"
					};
					
					Once this plugin is in place, you'll be able to use it to build and send emails in the same way as the stock
					ColdBox mail service plugin.
					
	Caveats		:	Emails sent through this service are NOT spooled. As such the user will have to wait whilst each email is sent,
					for emails which have attachments, this may take some time. If you are sending anything more than the smallest
					of attachments I would suggest that you modify this to use some form of spool, this may take some work though.
--->
<cfcomponent output="false" extends="coldbox.system.core.mail.MailService" cache="true">

	<cffunction name="init" access="public" output="false" returntype="PostBox" hint="I'm the class constructor method.">

			<!--- Plugin Properties --->
			<cfset setPluginName("PostBox") />
			<cfset setPluginDescription("This is a mail service which interfaces with PostMarkApp.com instead o the standard SMTP server.") />
			<cfset setPluginVersion("0.1") />
			<cfset setPluginAuthor("Robert Rawlins") />
			<cfset setPluginAuthorURL("http://weboffins.com") />
			
			<!--- Get the API key we'll be needing from the settings component. --->
			<cfset variables.postMarkApiKey = getSetting("PostMarkApiKey") />
			
			<!--- Super init it --->
			<cfset super.init() />
			
		<!--- Return an instance of this entity. --->
		<cfreturn this />
	</cffunction>

	<cffunction name="send" access="public" returntype="struct" output="true" hint="Send an email payload. Returns a struct: [error:boolean,errorArray:array,messageid:string]">
		<cfargument name="mail" required="true" type="coldbox.system.core.mail.Mail" hint="The mail payload to send." />

			<!--- Create a temporary local structure. --->
			<cfset var local = structNew() />
			
			<!--- Create a default return structure. --->
			<cfset local.rtnStruct = structNew() />
			<cfset local.rtnStruct.error = true />
			<cfset local.rtnStruct.errorArray = arrayNew(1) />
			
			<!--- First we'll start by validating the payload, to ensure everything is prepared to send. --->
			<cfif NOT mail.validate()>
				<!--- The payload does not validate. --->
				<!--- We need to prepare an error structure. --->
				<cfset arrayAppend(local.rtnStruct.errorArray, "Please check the basic mail fields of To, From and Body as they are empty. To: #arguments.mail.getTo()#, From: #arguments.mail.getFrom()#, Body Len = #arguments.mail.getBody().length()#.") />
				
				<!--- As the object hasn't validated at all we should quit processing here. --->
				<!--- We can do this by returning the result, which will now include our error details. --->
				<cfreturn local.rtnStruct />
			</cfif>
			
			<!--- We can also parse the tokens for the mail now. --->
			<cfset parseTokens(arguments.mail) />			

			<!--- If we've made it this far then then the payload should be fit for purpose. --->
			<!--- Get the information from the email payload. --->
			<cfset local.data = arguments.mail.getMemento() />

			<!--- We can now start to assemble our augmented payload ready to send to PostMark. --->
			<!--- Create a default array for the custom mail headers. --->
			<cfset local.headers = arrayNew(1) />
			<!--- And another one for the attachments. --->
			<cfset local.attachments = arrayNew(1) />
			
			<!--- Both customer headers and attachments are defined in the mail params for the coldbox mail payload. --->
			<!--- Loop over the mail params, we can then extract the headers and arrachments from it. --->
			<cfloop array="#mail.getMailParams()#" index="local.mailparam">
				<!--- Check that this header is a 'nam' element. --->
				<cfif structKeyExists(local.mailparam, "name")>					
					<!--- Append the encoded header structure into the array of headers. --->
					<cfset arrayAppend(local.headers, encodeHeader(local.mailparam)) />
				<!--- Now check to see if this mailparam is an attachment. --->
				<cfelseif structKeyExists(local.mailparam, "file")>						
					<!--- Append the encoded attachment structure to the array. --->
					<cfset arrayAppend(LOCAL.Attachments, encodeAttachment(local.mailparam)) />
				</cfif>
			</cfloop>
			
			<!--- Check to see if the nasmed header array has any length. --->
			<cfif arrayLen(local.headers)>
				<!--- We have some custom named headers to add to the mail. --->
				<!--- Add them to the payload structure. --->
				<cfset local.data["Headers"] = local.headers />
			</cfif>

			<!--- Check to see if we have any attachements. --->
			<cfif arrayLen(local.attachments)>
				<!--- We have some attachments to add to the mail. --->
				<!--- Add them to the payload structure. --->
				<cfset local.data["Attachments"] = local.attachments />
			</cfif>
			
			<!--- Now we're going to render the body contend for the email. --->
			<!--- We'll start by looking at the standard mail body, rather than any mailparts. --->
			<!--- We start by assessing what type has been set for the content. --->
			<cfif structKeyExists(local.data, "type") AND local.data["type"] EQ "html">
				<!--- This is an html email, set the body as an html body. --->
				<!--- Ammend the keys so that PostMark can understand them. --->
				<!--- This is because PostMark doesn't use a key named Body, but one named HTMLBody --->
				<cfset local.data["HtmlBody"] = local.data["Body"] />
			<cfelse>
				<!--- This has no specific type of something other thank html set, so we'll assume it's a plain text body. --->
				<!--- Ammend the keys so that PostMark can understand them. --->
				<!--- This is because PostMark doesn't use a key named Body, but one named HTMLBody --->
				<cfset local.data["TextBody"] = local.data["Body"] />
			</cfif>
			
			<!--- Now, we need to look for any other mail parts which may have been speficied. --->
			<!--- These will override any body content for the specific type which may have been set before. --->
			<!--- Loop over any mailports in the payload. --->
			<cfloop array="#arguments.mail.getMailParts()#" index="local.mailpart">
				<!--- We need to check the format of the mail part. --->
				<cfif local.mailpart.type EQ "html">
					<!--- This is an html mail part. --->
					<!--- Set the html body for the email as the content for this parameter. --->
					<cfset LOCAL.Data["HtmlBody"] = local.mailpart.body />
				<cfelseif local.mailpart.type EQ "plain" OR local.mailpart.type EQ "text">
					<!--- This is an text mail part. --->
					<!--- Set the html body for the email as the content for this parameter. --->
					<cfset local.data["TextBody"] = local.mailpart.body />
				</cfif>
			</cfloop>
						
			<!--- Render the email data as JSON. --->
			<!--- This is the format that PostMark like to receieve it in. --->
			<cfset local.jsonPacket = serializeJson(local.data) />
			
			<!--- Coldfusion can sometimes add a profix to the JSON, so we're going to clean it up. --->
			<cfset local.jsonPacketWithoutPrefix = Trim(Mid(local.jsonPacket, Find("{", local.jsonPacket), len(local.jsonPacket))) />

			<!--- We now send the JSON request to the PostMark web service API. --->
			<!--- This request has the possibility of failing, so we'll wrap it in a try/catch. --->
			<cftry>
				<!--- Post our request over to the API. --->
				<cfhttp url="https://api.postmarkapp.com/email" method="post" result="local.cfhttp" throwOnError="true">
					<cfhttpparam type="header" name="Accept" value="application/json" />
					<cfhttpparam type="header" name="Content-type" value="application/json" />
					<cfhttpparam type="header" name="X-Postmark-Server-Token" value="#variables.postMarkApiKey#" />
					<cfhttpparam type="body" encoded="no" value="#local.jsonPacketWithoutPrefix#" />
				</cfhttp>
				
				<!--- Catch any exceptions which might be thrown by this requets. --->
				<cfcatch type="any">
					<!--- This probably means that something substantial has gone wrong. --->
					<!--- We'll append the details of the error into an error structure. --->
					<cfset arrayAppend(local.rtnStruct.errorArray,"Error sending mail. #cfcatch.message# : #cfcatch.detail# : #cfcatch.stackTrace#") />
				
					<!--- Return this structure, this will abort any further processing from the plugin. --->
					<cfreturn local.rtnStruct />
				</cfcatch>
			</cftry>
			
			<!--- If we've made it this far then our request to PostMark has been completed. --->
			<!--- We can now reformat this result into something which is recognisable to a ColdBox application. --->
			<cfset local.rtnStruct = reformatPostMarkResponse(deserializeJSON(local.cfhttp.FileContent.toString()))  />
			
		<!--- Return the result from the request. --->
		<cfreturn local.rtnStruct />
	</cffunction>
	
	<cffunction name="encodeHeader" access="private" returntype="struct" hint="I encode named headers so that PostMark likes it">
		<cfargument name="MailParam" required="true" type="struct" hint="I'm the file path for the attachment." />

			<!--- Create a temporary local structure. --->
			<cfset var local = structNew() />
			
			<!--- This is a named custom header. Build a structure for it. --->
			<cfset local.this_header = structNew() />
					
			<!--- Add the name and value to this structure. --->
			<cfset local.this_header["name"] = arguments.mailparam["name"] />	
			<cfset local.this_header["value"] = arguments.mailparam["value"] />

		<!--- Return the structure which defines the header. --->
		<cfreturn local.this_header />
	</cffunction>
	
	<cffunction name="encodeAttachment" access="private" returntype="struct" hint="I encode an attachment so that PostMark likes it.">
		<cfargument name="MailParam" required="true" type="struct" hint="I'm the file path for the attachment." />

			<!--- Create a temporary local structure. --->
			<cfset var local = structNew() />
			
			<!--- This is an attachement which needs to be added to the email. --->
			<!--- Create a structure for this. --->
			<cfset local.attachment = structNew() />
			
			<!--- Read the file so we can get it's content. --->
			<cffile action="readbinary" file="#arguments.mailparam.file#" variable="local.objBinaryData" />
			
			<!--- Encode the file path. --->
			<cfset local.base64 = toBase64(local.objBinaryData) />
			
			<!--- Build the structure. --->
			<cfset local.attachment["Name"] = GetFileFromPath(arguments.mailparam.file) />
			<cfset local.attachment["Content"] = local.base64 />
			
			<!--- We now need to check if a filetype was given for this attacgment. --->
			<cfif structKeyExists(arguments.mailparam, "filetype")>
				<!--- A specific file type was given to us, we'll use this. --->
				<cfset local.attachment["ContentType"] = arguments.mailparam.filetype />
			<cfelse>
				<!--- No file type was given, so we'll try to self assess this using the file extension. --->
				<cfset local.attachment["ContentType"] = getFileMimeType(arguments.mailparam.file) />
			</cfif>
					
		<!--- Return the structure which defines this attachment. --->
		<cfreturn local.attachment />
	</cffunction>
	
	<cffunction name="getFileMimeType" access="private" returntype="string" output="false" hint="I calculate the MIME type for a given file.">   
	    <cfargument name="filePath" type="string" required="true" hint="I'm the path to the file to be tested." />
	    
	    <!--- Return the mime type of this file. --->
	    <cfreturn getPageContext().getServletContext().getMimeType(arguments.filePath) />
	</cffunction>	
	
	<cffunction name="reformatPostMarkResponse" access="private" returntype="struct" hint="I format the PostMarkApp return result into one which conforms to the coldbox mailer service.">
		<cfargument name="PostMarkReturnStruct" required="true" type="struct" hint="I'm the returned structure from postmark" />
		
			<!--- Create a temporary local structure. --->
			<cfset var local = structNew() />
		
			<!--- Check to see if this returned message is OK or not. --->
			<cfif PostMarkReturnStruct.Message EQ "OK">
				<!--- This message was sent just fine. --->
				<!--- Set the error result to false. --->
				<cfset local.ReturnStruct["error"] = False />
				
				<!--- We're also going to append the message ID. --->
				<!--- This is not a value which exists in the standard coldbox library but we'll add it. --->
				<cfset local.ReturnStruct["message_id"] = PostMarkReturnStruct["MessageID"] />
			<cfelse>
				<!--- If this message was not OK then we have an error on our hands. --->
				<!--- Create an array for us to put the errors into. --->
				<cfset local.ReturnStruct["errorArray"] = arrayNew(1) />
								
				<!--- Set the error variable to true. --->
				<cfset local.ReturnStruct["error"] = True />
				
				<!--- We're also going to append the error code and message into the error array. --->
				<cfset arrayAppend(local.ReturnStruct["errorArray"], "#PostMarkReturnStruct['ErrorCode']# - #PostMarkReturnStruct['Message']#") />
			</cfif>
					
		<!--- Return the reformated structure. --->
		<cfreturn local.ReturnStruct />
	</cffunction>

</cfcomponent>