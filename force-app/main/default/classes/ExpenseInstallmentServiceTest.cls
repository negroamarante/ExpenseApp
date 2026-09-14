@IsTest
private class ExpenseInstallmentServiceTest {
  @TestSetup
  static void setup() {
    insert new Monthly_Budget__c(
      Month_Start__c = Date.newInstance(2026, 9, 1),
      Budget_Amount__c = 2000000
    );
  }

  @IsTest
  static void testInsertCreatesInstallmentsAndLookup() {
    Test.startTest();
    Expense__c expense = new Expense__c(
      Description__c = 'Compra en cuotas',
      Purchase_Date__c = Date.newInstance(2026, 9, 15),
      Total_Amount__c = 600000,
      Number_Of_Installments__c = '6',
      Person__c = 'Diego'
    );
    insert expense;
    Test.stopTest();

    expense = [
      SELECT Monthly_Budget__c, Monthly_Budget__r.Month_Start__c
      FROM Expense__c
      WHERE Id = :expense.Id
    ];
    System.assertEquals(
      Date.newInstance(2026, 9, 1),
      expense.Monthly_Budget__r.Month_Start__c
    );

    List<Expense_Installment__c> lines = [
      SELECT Month_Start__c, Installment_Number__c, Amount__c, Monthly_Budget__c
      FROM Expense_Installment__c
      WHERE Expense__c = :expense.Id
      ORDER BY Installment_Number__c
    ];
    System.assertEquals(6, lines.size());
    System.assertEquals(100000, lines[0].Amount__c);
    System.assertEquals(Date.newInstance(2026, 9, 1), lines[0].Month_Start__c);
    System.assertEquals(Date.newInstance(2027, 2, 1), lines[5].Month_Start__c);
    System.assertEquals(expense.Monthly_Budget__c, lines[0].Monthly_Budget__c);
  }

  @IsTest
  static void testReducingInstallmentsDeletesExtraLines() {
    Expense__c expense = new Expense__c(
      Description__c = 'Compra en cuotas',
      Purchase_Date__c = Date.newInstance(2026, 9, 15),
      Total_Amount__c = 600000,
      Number_Of_Installments__c = '6',
      Person__c = 'Diego'
    );
    insert expense;

    Test.startTest();
    expense.Number_Of_Installments__c = '2';
    update expense;
    Test.stopTest();

    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM Expense_Installment__c
        WHERE Expense__c = :expense.Id
      ]
    );
  }

  @IsTest
  static void testBudgetStoresCommittedAndRollover() {
    insert new Expense__c(
      Description__c = 'Supermercado',
      Purchase_Date__c = Date.newInstance(2026, 9, 5),
      Total_Amount__c = 300000,
      Number_Of_Installments__c = '1',
      Person__c = 'Diego'
    );

    Monthly_Budget__c sept = [
      SELECT Committed__c, Rollover_In__c, Available__c
      FROM Monthly_Budget__c
      WHERE Month_Start__c = :Date.newInstance(2026, 9, 1)
    ];
    System.assertEquals(300000, sept.Committed__c);
    System.assertEquals(0, sept.Rollover_In__c);
    System.assertEquals(1700000, sept.Available__c);
  }

  @IsTest
  static void testBackfillCreatesMissingInstallments() {
    ExpenseInstallmentService.isRunning = true;
    Expense__c expense = new Expense__c(
      Description__c = 'Sin trigger',
      Purchase_Date__c = Date.newInstance(2026, 9, 5),
      Total_Amount__c = 120000,
      Number_Of_Installments__c = '1',
      Person__c = 'Diego'
    );
    insert expense;
    ExpenseInstallmentService.isRunning = false;

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Expense_Installment__c
        WHERE Expense__c = :expense.Id
      ]
    );

    Test.startTest();
    Integer count = ExpenseInstallmentService.backfillAll();
    Test.stopTest();

    System.assert(count >= 1);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Expense_Installment__c
        WHERE Expense__c = :expense.Id
      ]
    );
  }
}
