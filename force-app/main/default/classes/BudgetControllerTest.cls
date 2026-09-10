@IsTest
private class BudgetControllerTest {
  @TestSetup
  static void setup() {
    insert new Monthly_Budget__c(
      Month_Start__c = Date.newInstance(2026, 9, 1),
      Budget_Amount__c = 2000000
    );
  }

  @IsTest
  static void testMonthSummaryNoExpenses() {
    Test.startTest();
    BudgetController.MonthSummary summary = BudgetController.getMonthSummary(
      Date.newInstance(2026, 9, 15)
    );
    Test.stopTest();

    System.assertEquals(2000000, summary.budgetAmount);
    System.assertEquals(0, summary.committedAmount);
    System.assertEquals(2000000, summary.availableAmount);
    System.assertEquals(true, summary.hasBudget);
    System.assertEquals(0, summary.expenses.size());
  }

  @IsTest
  static void testSingleInstallmentExpense() {
    insert new Expense__c(
      Description__c = 'Supermercado',
      Purchase_Date__c = Date.newInstance(2026, 9, 5),
      Total_Amount__c = 300000,
      Number_Of_Installments__c = '1',
      Person__c = 'Diego'
    );

    Test.startTest();
    BudgetController.MonthSummary summary = BudgetController.getMonthSummary(
      Date.newInstance(2026, 9, 1)
    );
    Test.stopTest();

    System.assertEquals(300000, summary.committedAmount);
    System.assertEquals(1700000, summary.availableAmount);
    System.assertEquals(1, summary.expenses.size());
    System.assertEquals(1, summary.expenses[0].installmentNumber);
  }

  @IsTest
  static void testMultiInstallmentExpenseAcrossYearRollover() {
    insert new Expense__c(
      Description__c = 'Compra en cuotas',
      Purchase_Date__c = Date.newInstance(2026, 9, 15),
      Total_Amount__c = 600000,
      Number_Of_Installments__c = '6',
      Person__c = 'Diego'
    );

    Test.startTest();
    BudgetController.MonthSummary septSummary = BudgetController.getMonthSummary(
      Date.newInstance(2026, 9, 1)
    );
    BudgetController.MonthSummary febSummary = BudgetController.getMonthSummary(
      Date.newInstance(2027, 2, 1)
    );
    BudgetController.MonthSummary marchSummary = BudgetController.getMonthSummary(
      Date.newInstance(2027, 3, 1)
    );
    Test.stopTest();

    System.assertEquals(100000, septSummary.committedAmount);
    System.assertEquals(100000, febSummary.committedAmount);
    System.assertEquals(6, febSummary.expenses[0].installmentNumber);
    System.assertEquals(0, marchSummary.committedAmount);
  }

  @IsTest
  static void testExistingPlusNewInstallmentExample() {
    insert new Expense__c(
      Description__c = 'Compra previa',
      Purchase_Date__c = Date.newInstance(2026, 9, 1),
      Total_Amount__c = 300000,
      Number_Of_Installments__c = '1',
      Person__c = 'Diego'
    );
    insert new Expense__c(
      Description__c = 'Compra nueva',
      Purchase_Date__c = Date.newInstance(2026, 9, 10),
      Total_Amount__c = 600000,
      Number_Of_Installments__c = '6',
      Person__c = 'Emi'
    );

    Test.startTest();
    BudgetController.MonthSummary summary = BudgetController.getMonthSummary(
      Date.newInstance(2026, 9, 1)
    );
    Test.stopTest();

    System.assertEquals(400000, summary.committedAmount);
    System.assertEquals(1600000, summary.availableAmount);
  }

  @IsTest
  static void testMonthWithoutBudget() {
    Test.startTest();
    BudgetController.MonthSummary summary = BudgetController.getMonthSummary(
      Date.newInstance(2027, 1, 1)
    );
    Test.stopTest();

    System.assertEquals(false, summary.hasBudget);
    System.assertEquals(0, summary.budgetAmount);
  }

  @IsTest
  static void testSaveBudgetInsertAndUpdate() {
    Test.startTest();
    BudgetController.saveBudget(Date.newInstance(2026, 10, 1), 1900000);
    BudgetController.saveBudget(Date.newInstance(2026, 10, 1), 2000000);
    Test.stopTest();

    Monthly_Budget__c updated = [
      SELECT Budget_Amount__c
      FROM Monthly_Budget__c
      WHERE Month_Start__c = :Date.newInstance(2026, 10, 1)
    ];
    System.assertEquals(2000000, updated.Budget_Amount__c);
  }

  @IsTest
  static void testGetPreviousMonthBudgetAmount() {
    Test.startTest();
    Decimal previous = BudgetController.getPreviousMonthBudgetAmount(
      Date.newInstance(2026, 10, 1)
    );
    Test.stopTest();

    System.assertEquals(2000000, previous);
  }
}
