public with sharing class ErrorNotifier {
  @TestVisible
  private static Integer notificationCount = 0;

  public static void notify(String subject, String message) {
    notificationCount++;
    try {
      Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
      email.setToAddresses(new List<String>{ UserInfo.getUserEmail() });
      email.setSubject(subject);
      email.setPlainTextBody(message);
      email.setSaveAsActivity(false);
      Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'ErrorNotifier failed to send email: ' + e.getMessage()
      );
    }
  }
}
