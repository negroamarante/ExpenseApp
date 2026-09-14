public with sharing class ExpenseInstallmentService {
  @TestVisible
  static Boolean isRunning = false;

  public static void syncFromTrigger(
    List<Expense__c> newList,
    Map<Id, Expense__c> oldMap
  ) {
    if (isRunning) {
      return;
    }
    List<Expense__c> toSync = new List<Expense__c>();
    for (Expense__c expense : newList) {
      if (oldMap == null || fieldsChanged(expense, oldMap.get(expense.Id))) {
        toSync.add(expense);
      }
    }
    if (!toSync.isEmpty()) {
      syncExpenses(toSync, oldMap);
    }
  }

  public static void handleDelete(List<Expense__c> oldList) {
    if (isRunning) {
      return;
    }
    Date fromMonth = earliestMonth(oldList, null);
    if (fromMonth != null) {
      isRunning = true;
      try {
        recalculateFrom(fromMonth);
      } finally {
        isRunning = false;
      }
    }
  }

  public static void handleBudgetChange(
    List<Monthly_Budget__c> newList,
    Map<Id, Monthly_Budget__c> oldMap
  ) {
    if (isRunning) {
      return;
    }
    Date fromMonth;
    for (Monthly_Budget__c budget : newList) {
      if (
        oldMap == null ||
        budget.Budget_Amount__c != oldMap.get(budget.Id).Budget_Amount__c
      ) {
        if (fromMonth == null || budget.Month_Start__c < fromMonth) {
          fromMonth = budget.Month_Start__c;
        }
      }
    }
    if (fromMonth != null) {
      isRunning = true;
      try {
        recalculateFrom(fromMonth);
      } finally {
        isRunning = false;
      }
    }
  }

  public static void handleBudgetDelete(List<Monthly_Budget__c> oldList) {
    if (isRunning) {
      return;
    }
    Date fromMonth;
    for (Monthly_Budget__c budget : oldList) {
      if (fromMonth == null || budget.Month_Start__c < fromMonth) {
        fromMonth = budget.Month_Start__c;
      }
    }
    if (fromMonth != null) {
      isRunning = true;
      try {
        recalculateFrom(fromMonth);
      } finally {
        isRunning = false;
      }
    }
  }

  public static Integer backfillAll() {
    List<Expense__c> expenses = [
      SELECT
        Id,
        Purchase_Date__c,
        Total_Amount__c,
        Number_Of_Installments__c,
        Installment_Amount__c,
        Monthly_Budget__c
      FROM Expense__c
    ];
    if (expenses.isEmpty()) {
      return 0;
    }
    syncExpenses(expenses, null);
    return expenses.size();
  }

  private static void syncExpenses(
    List<Expense__c> expenses,
    Map<Id, Expense__c> oldMap
  ) {
    isRunning = true;
    try {
      Date fromMonth = earliestMonth(expenses, oldMap);
      Set<Date> months = new Set<Date>();
      for (Expense__c expense : expenses) {
        months.addAll(monthsFor(expense));
      }
      if (oldMap != null) {
        for (Expense__c expense : expenses) {
          Expense__c previous = oldMap.get(expense.Id);
          if (previous != null) {
            months.addAll(monthsFor(previous));
          }
        }
      }

      Map<Date, Monthly_Budget__c> budgetsByMonth = ensureBudgets(months);

      Set<Id> expenseIds = new Map<Id, Expense__c>(expenses).keySet();
      delete [
        SELECT Id
        FROM Expense_Installment__c
        WHERE Expense__c IN :expenseIds
      ];

      List<Expense_Installment__c> installments = new List<Expense_Installment__c>();
      List<Expense__c> expenseUpdates = new List<Expense__c>();
      for (Expense__c expense : expenses) {
        List<Date> expenseMonths = monthsFor(expense);
        Decimal amount = expense.Installment_Amount__c;
        Id purchaseBudgetId = budgetsByMonth.get(expenseMonths[0]).Id;
        if (expense.Monthly_Budget__c != purchaseBudgetId) {
          expenseUpdates.add(
            new Expense__c(
              Id = expense.Id,
              Monthly_Budget__c = purchaseBudgetId
            )
          );
        }
        for (Integer i = 0; i < expenseMonths.size(); i++) {
          Date monthStart = expenseMonths[i];
          installments.add(
            new Expense_Installment__c(
              Expense__c = expense.Id,
              Monthly_Budget__c = budgetsByMonth.get(monthStart).Id,
              Month_Start__c = monthStart,
              Installment_Number__c = i + 1,
              Amount__c = amount
            )
          );
        }
      }
      if (!installments.isEmpty()) {
        insert installments;
      }
      if (!expenseUpdates.isEmpty()) {
        update expenseUpdates;
      }
      if (fromMonth != null) {
        recalculateFrom(fromMonth);
      }
    } finally {
      isRunning = false;
    }
  }

  private static void recalculateFrom(Date fromMonth) {
    Decimal rolloverIn = 0;
    List<Monthly_Budget__c> previous = [
      SELECT Available__c
      FROM Monthly_Budget__c
      WHERE Month_Start__c < :fromMonth
      ORDER BY Month_Start__c DESC
      LIMIT 1
    ];
    if (!previous.isEmpty() && previous[0].Available__c != null) {
      rolloverIn = previous[0].Available__c;
    }

    List<Monthly_Budget__c> budgets = [
      SELECT Id, Month_Start__c, Budget_Amount__c, Committed__c, Rollover_In__c
      FROM Monthly_Budget__c
      WHERE Month_Start__c >= :fromMonth
      ORDER BY Month_Start__c ASC
    ];
    if (budgets.isEmpty()) {
      return;
    }

    Set<Id> budgetIds = new Map<Id, Monthly_Budget__c>(budgets).keySet();
    Map<Id, Decimal> committedByBudget = new Map<Id, Decimal>();
    for (AggregateResult row : [
      SELECT Monthly_Budget__c budgetId, SUM(Amount__c) total
      FROM Expense_Installment__c
      WHERE Monthly_Budget__c IN :budgetIds
      GROUP BY Monthly_Budget__c
    ]) {
      committedByBudget.put(
        (Id) row.get('budgetId'),
        (Decimal) row.get('total')
      );
    }

    for (Monthly_Budget__c budget : budgets) {
      Decimal committed = committedByBudget.containsKey(budget.Id)
        ? committedByBudget.get(budget.Id)
        : 0;
      budget.Committed__c = committed;
      budget.Rollover_In__c = rolloverIn;
      Decimal amount = budget.Budget_Amount__c == null
        ? 0
        : budget.Budget_Amount__c;
      rolloverIn = (amount + rolloverIn) - committed;
    }
    update budgets;
  }

  private static Map<Date, Monthly_Budget__c> ensureBudgets(
    Set<Date> monthStarts
  ) {
    Map<Date, Monthly_Budget__c> byMonth = new Map<Date, Monthly_Budget__c>();
    if (monthStarts == null || monthStarts.isEmpty()) {
      return byMonth;
    }
    for (Monthly_Budget__c budget : [
      SELECT Id, Month_Start__c, Budget_Amount__c, Committed__c, Rollover_In__c
      FROM Monthly_Budget__c
      WHERE Month_Start__c IN :monthStarts
    ]) {
      byMonth.put(budget.Month_Start__c, budget);
    }
    List<Monthly_Budget__c> toInsert = new List<Monthly_Budget__c>();
    for (Date monthStart : monthStarts) {
      if (!byMonth.containsKey(monthStart)) {
        toInsert.add(
          new Monthly_Budget__c(
            Month_Start__c = monthStart,
            Budget_Amount__c = 0
          )
        );
      }
    }
    if (!toInsert.isEmpty()) {
      insert toInsert;
      for (Monthly_Budget__c budget : toInsert) {
        byMonth.put(budget.Month_Start__c, budget);
      }
    }
    return byMonth;
  }

  private static Boolean fieldsChanged(
    Expense__c current,
    Expense__c previous
  ) {
    return current.Purchase_Date__c != previous.Purchase_Date__c ||
      current.Total_Amount__c != previous.Total_Amount__c ||
      current.Number_Of_Installments__c != previous.Number_Of_Installments__c;
  }

  private static Date earliestMonth(
    List<Expense__c> expenses,
    Map<Id, Expense__c> oldMap
  ) {
    Date fromMonth;
    for (Expense__c expense : expenses) {
      fromMonth = minDate(fromMonth, expense.Purchase_Date__c.toStartOfMonth());
      if (oldMap != null && oldMap.containsKey(expense.Id)) {
        fromMonth = minDate(
          fromMonth,
          oldMap.get(expense.Id).Purchase_Date__c.toStartOfMonth()
        );
      }
    }
    return fromMonth;
  }

  private static Date minDate(Date left, Date right) {
    if (left == null) {
      return right;
    }
    if (right == null || left < right) {
      return left;
    }
    return right;
  }

  private static List<Date> monthsFor(Expense__c expense) {
    Integer count = Integer.valueOf(expense.Number_Of_Installments__c);
    Date start = expense.Purchase_Date__c.toStartOfMonth();
    List<Date> months = new List<Date>();
    for (Integer i = 0; i < count; i++) {
      months.add(start.addMonths(i));
    }
    return months;
  }
}
