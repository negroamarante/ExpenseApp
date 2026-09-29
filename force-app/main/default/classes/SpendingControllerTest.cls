@IsTest
private class SpendingControllerTest {
  @IsTest
  static void testGetMonthSpendingReturnsOnlySpendingExpenses() {
    insert new Monthly_Budget__c(
      Month_Start__c = Date.newInstance(2026, 9, 1),
      Budget_Amount__c = 2000000
    );

    insert new List<Expense__c>{
      new Expense__c(
        Description__c = 'Cuota tarjeta presupuesto',
        Purchase_Date__c = Date.newInstance(2026, 9, 5),
        Total_Amount__c = 300000,
        Number_Of_Installments__c = '1',
        Person__c = 'Diego',
        Counts_Toward_Budget__c = true,
        Counts_Toward_Spending__c = false,
        Payment_Method__c = 'Tarjeta presupuesto'
      ),
      new Expense__c(
        Description__c = 'Super efectivo',
        Purchase_Date__c = Date.newInstance(2026, 9, 10),
        Total_Amount__c = 45000,
        Number_Of_Installments__c = '1',
        Person__c = 'Emi',
        Counts_Toward_Budget__c = false,
        Counts_Toward_Spending__c = true,
        Payment_Method__c = 'Efectivo'
      ),
      new Expense__c(
        Description__c = 'Compra dual',
        Purchase_Date__c = Date.newInstance(2026, 9, 12),
        Total_Amount__c = 90000,
        Number_Of_Installments__c = '1',
        Person__c = 'Diego',
        Counts_Toward_Budget__c = true,
        Counts_Toward_Spending__c = true,
        Payment_Method__c = 'Tarjeta presupuesto'
      ),
      new Expense__c(
        Description__c = 'Mes anterior',
        Purchase_Date__c = Date.newInstance(2026, 8, 20),
        Total_Amount__c = 10000,
        Number_Of_Installments__c = '1',
        Person__c = 'Diego',
        Counts_Toward_Budget__c = false,
        Counts_Toward_Spending__c = true,
        Payment_Method__c = 'Otra tarjeta'
      )
    };

    Test.startTest();
    SpendingController.MonthSpending summary = SpendingController.getMonthSpending(
      Date.newInstance(2026, 9, 1)
    );
    Test.stopTest();

    System.assertEquals(2, summary.expenses.size());
    System.assertEquals(135000, summary.totalSpent);

    Monthly_Budget__c sept = [
      SELECT Committed__c
      FROM Monthly_Budget__c
      WHERE Month_Start__c = :Date.newInstance(2026, 9, 1)
    ];
    // budget-only 300k + dual 90k; cash spending must not count
    System.assertEquals(390000, sept.Committed__c);
  }

  @IsTest
  static void testSpendingInstallmentsAppearInMatchingMonths() {
    insert new Expense__c(
      Description__c = 'TV otra tarjeta',
      Purchase_Date__c = Date.newInstance(2026, 9, 8),
      Total_Amount__c = 300000,
      Number_Of_Installments__c = '3',
      Person__c = 'Diego',
      Counts_Toward_Budget__c = false,
      Counts_Toward_Spending__c = true,
      Payment_Method__c = 'Otra tarjeta'
    );

    System.assertEquals(3, [SELECT COUNT() FROM Expense_Installment__c]);

    SpendingController.MonthSpending sept = SpendingController.getMonthSpending(
      Date.newInstance(2026, 9, 1)
    );
    SpendingController.MonthSpending nov = SpendingController.getMonthSpending(
      Date.newInstance(2026, 11, 1)
    );

    System.assertEquals(1, sept.expenses.size());
    System.assertEquals(100000, sept.totalSpent);
    System.assertEquals(1, sept.expenses[0].installmentNumber);
    System.assertEquals(100000, nov.totalSpent);
    System.assertEquals(3, nov.expenses[0].installmentNumber);

    // spending-only installments must not inflate límite cupo committed
    Monthly_Budget__c septBudget = [
      SELECT Committed__c
      FROM Monthly_Budget__c
      WHERE Month_Start__c = :Date.newInstance(2026, 9, 1)
    ];
    System.assertEquals(0, septBudget.Committed__c);
  }
}
