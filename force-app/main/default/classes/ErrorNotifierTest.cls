@IsTest
private class ErrorNotifierTest {
  @IsTest
  static void testNotifySendsEmailToCurrentUser() {
    Test.startTest();
    ErrorNotifier.notify('Asunto de prueba', 'Cuerpo de prueba');
    Test.stopTest();

    System.assertEquals(1, ErrorNotifier.notificationCount);
  }
}
