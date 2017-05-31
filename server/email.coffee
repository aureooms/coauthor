unless process.env['MAIL_URL']?
  console.warn "MAIL_URL not sent -- email notifications won't work!"

Accounts.emailTemplates.siteName = 'Coauthor'
Accounts.emailTemplates.from = 'coauthor@ulb.ac.be'
Accounts.emailTemplates.verifyEmail.subject = (user) ->
  "Email confirmation for Coauthor"
Accounts.emailTemplates.verifyEmail.text = (user, link) -> """
  Welcome to Coauthor, #{user.emails[0].address}!

  You (or someone claiming to be you) just registered an account with username
  "#{user.username}" on the Coauthor collaboration website,
  #{Meteor.absoluteUrl()}

  To confirm that your email address is accurate (necessary for email
  notifications to work), please click on the following link:

  #{link}
  
  If you have any questions or concerns, please reply to this email.
"""

Accounts.config
  sendVerificationEmail: true

#Email.send
#  from: 'coauthor@ulb.ac.be'
#  to: 'edemaine@mit.edu'
#  subject: 'Testing...'
#  html: '<p>Welcome to Coauthor!</p>We hope you like your stay :)'
