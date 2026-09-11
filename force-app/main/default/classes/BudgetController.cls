public with sharing class BudgetController {
  public class MonthSummary {
    @AuraEnabled
    public Date monthStart;
    @AuraEnabled
    public String monthLabel;
    @AuraEnabled
    public Decimal budgetAmount;
    @AuraEnabled
    public Decimal rolloverAmount;
    @AuraEnabled
    public Decimal committedAmount;
    @AuraEnabled
    public Decimal availableAmount;
    @AuraEnabled
    public Decimal percentUsed;
    @AuraEnabled
    public Boolean hasBudget;
    @AuraEnabled
    public List<ExpenseItem> expenses;
  }

  public class ExpenseItem {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Date purchaseDate;
    @AuraEnabled
    public Decimal totalAmount;
    @AuraEnabled
    public Integer numberOfInstallments;
    @AuraEnabled
    public Decimal installmentAmount;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String person;
    @AuraEnabled
    public Integer installmentNumber;
  }

  @AuraEnabled(cacheable=true)
  public static MonthSummary getMonthSummary(Date monthStart) {
    Date normalizedStart = monthStart.toStartOfMonth();
    Date monthEnd = normalizedStart.addMonths(1).addDays(-1);
    Date earliestMonth = getEarliestMonth(normalizedStart);

    Map<Date, Decimal> budgetByMonth = getBudgetsByMonth(
      earliestMonth,
      normalizedStart
    );
    Map<Date, List<Expense__c>> expensesByMonth = getExpensesByMonth(
      earliestMonth,
      normalizedStart,
      monthEnd
    );

    // Roll every prior month's leftover (or shortfall) forward so it lands on
    // the requested month: a month that ends with money left over hands that
    // surplus to the next month's budget, and a month that overspends hands
    // over a deficit that eats into the next month's budget instead.
    Decimal rollover = 0;
    Date cursor = earliestMonth;
    while (cursor < normalizedStart) {
      Decimal ownBudget = budgetByMonth.containsKey(cursor)
        ? budgetByMonth.get(cursor)
        : 0;
      Decimal committed = sumInstallments(expensesByMonth.get(cursor));
      rollover = (ownBudget + rollover) - committed;
      cursor = cursor.addMonths(1);
    }

    MonthSummary summary = new MonthSummary();
    summary.monthStart = normalizedStart;
    summary.monthLabel = formatMonthLabel(normalizedStart);
    summary.rolloverAmount = rollover;
    summary.budgetAmount = budgetByMonth.containsKey(normalizedStart)
      ? budgetByMonth.get(normalizedStart)
      : 0;
    summary.hasBudget = summary.budgetAmount != 0 || rollover != 0;
    summary.expenses = new List<ExpenseItem>();

    List<Expense__c> requestedMonthExpenses = expensesByMonth.get(
      normalizedStart
    );
    if (requestedMonthExpenses != null) {
      for (Expense__c exp : requestedMonthExpenses) {
        ExpenseItem item = new ExpenseItem();
        item.id = exp.Id;
        item.description = exp.Description__c;
        item.purchaseDate = exp.Purchase_Date__c;
        item.totalAmount = exp.Total_Amount__c;
        item.numberOfInstallments = Integer.valueOf(
          exp.Number_Of_Installments__c
        );
        item.installmentAmount = exp.Installment_Amount__c;
        item.category = exp.Category__c;
        item.person = exp.Person__c;
        item.installmentNumber =
          monthsBetween(exp.Purchase_Date__c, normalizedStart) + 1;
        summary.expenses.add(item);
      }
    }

    Decimal effectiveBudget = summary.budgetAmount + rollover;
    summary.committedAmount = sumInstallments(requestedMonthExpenses);
    summary.availableAmount = effectiveBudget - summary.committedAmount;
    summary.percentUsed = effectiveBudget > 0
      ? (summary.committedAmount / effectiveBudget * 100).setScale(0)
      : 0;

    return summary;
  }

  @AuraEnabled
  public static void saveBudget(Date monthStart, Decimal amount) {
    Date normalizedStart = monthStart.toStartOfMonth();
    Monthly_Budget__c budget = getBudgetRecord(normalizedStart);
    Boolean isNew = budget == null;
    if (isNew) {
      budget = new Monthly_Budget__c(Month_Start__c = normalizedStart);
    }
    budget.Budget_Amount__c = amount;

    try {
      List<Monthly_Budget__c> records = new List<Monthly_Budget__c>{ budget };
      List<Monthly_Budget__c> safeRecords = (List<Monthly_Budget__c>) Security.stripInaccessible(
          isNew ? AccessType.CREATABLE : AccessType.UPDATABLE,
          records
        )
        .getRecords();
      upsert safeRecords[0];
    } catch (Exception e) {
      AuraHandledException ex = new AuraHandledException(e.getMessage());
      ex.setMessage(e.getMessage());
      throw ex;
    }
  }

  @AuraEnabled(cacheable=true)
  public static Decimal getPreviousMonthBudgetAmount(Date monthStart) {
    Date previousMonth = monthStart.toStartOfMonth().addMonths(-1);
    Monthly_Budget__c budget = getBudgetRecord(previousMonth);
    return budget != null ? budget.Budget_Amount__c : null;
  }

  private static Monthly_Budget__c getBudgetRecord(Date normalizedStart) {
    List<Monthly_Budget__c> budgets = [
      SELECT Id, Month_Start__c, Budget_Amount__c
      FROM Monthly_Budget__c
      WHERE Month_Start__c = :normalizedStart
      WITH USER_MODE
      LIMIT 1
    ];
    return budgets.isEmpty() ? null : budgets[0];
  }

  private static Date getEarliestMonth(Date normalizedStart) {
    Date earliest = normalizedStart;

    List<Monthly_Budget__c> earliestBudget = [
      SELECT Month_Start__c
      FROM Monthly_Budget__c
      WITH USER_MODE
      ORDER BY Month_Start__c ASC
      LIMIT 1
    ];
    if (
      !earliestBudget.isEmpty() &&
      earliestBudget[0].Month_Start__c < earliest
    ) {
      earliest = earliestBudget[0].Month_Start__c;
    }

    List<Expense__c> earliestExpense = [
      SELECT Purchase_Date__c
      FROM Expense__c
      WITH USER_MODE
      ORDER BY Purchase_Date__c ASC
      LIMIT 1
    ];
    if (!earliestExpense.isEmpty()) {
      Date expenseMonth = earliestExpense[0].Purchase_Date__c.toStartOfMonth();
      if (expenseMonth < earliest) {
        earliest = expenseMonth;
      }
    }

    return earliest;
  }

  private static Map<Date, Decimal> getBudgetsByMonth(
    Date earliestMonth,
    Date normalizedStart
  ) {
    Map<Date, Decimal> result = new Map<Date, Decimal>();
    for (Monthly_Budget__c b : [
      SELECT Month_Start__c, Budget_Amount__c
      FROM Monthly_Budget__c
      WHERE
        Month_Start__c >= :earliestMonth
        AND Month_Start__c <= :normalizedStart
      WITH USER_MODE
    ]) {
      result.put(b.Month_Start__c, b.Budget_Amount__c);
    }
    return result;
  }

  private static Map<Date, List<Expense__c>> getExpensesByMonth(
    Date earliestMonth,
    Date normalizedStart,
    Date monthEnd
  ) {
    Map<Date, List<Expense__c>> result = new Map<Date, List<Expense__c>>();
    for (Expense__c exp : [
      SELECT
        Id,
        Description__c,
        Purchase_Date__c,
        Total_Amount__c,
        Number_Of_Installments__c,
        Installment_Amount__c,
        End_Date__c,
        Category__c,
        Person__c
      FROM Expense__c
      WHERE Purchase_Date__c <= :monthEnd AND End_Date__c >= :earliestMonth
      WITH USER_MODE
      ORDER BY Purchase_Date__c DESC
    ]) {
      Date monthCursor = exp.Purchase_Date__c.toStartOfMonth();
      Date lastInstallmentMonth = exp.End_Date__c.toStartOfMonth();
      while (
        monthCursor <= lastInstallmentMonth &&
        monthCursor <= normalizedStart
      ) {
        if (monthCursor >= earliestMonth) {
          if (!result.containsKey(monthCursor)) {
            result.put(monthCursor, new List<Expense__c>());
          }
          result.get(monthCursor).add(exp);
        }
        monthCursor = monthCursor.addMonths(1);
      }
    }
    return result;
  }

  private static Decimal sumInstallments(List<Expense__c> expenses) {
    Decimal total = 0;
    if (expenses != null) {
      for (Expense__c exp : expenses) {
        total += exp.Installment_Amount__c;
      }
    }
    return total;
  }

  private static Integer monthsBetween(Date startDate, Date targetMonthStart) {
    return (targetMonthStart.year() - startDate.year()) * 12 +
      (targetMonthStart.month() - startDate.month());
  }

  private static String formatMonthLabel(Date monthStart) {
    List<String> monthNames = new List<String>{
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre'
    };
    return monthNames[monthStart.month() - 1] +
      ' ' +
      String.valueOf(monthStart.year());
  }
}
