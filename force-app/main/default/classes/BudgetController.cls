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

    MonthSummary summary = new MonthSummary();
    summary.monthStart = normalizedStart;
    summary.monthLabel = formatMonthLabel(normalizedStart);
    summary.expenses = new List<ExpenseItem>();

    List<Monthly_Budget__c> budgets = [
      SELECT Budget_Amount__c, Rollover_In__c, Committed__c, Available__c
      FROM Monthly_Budget__c
      WHERE Month_Start__c = :normalizedStart
      WITH USER_MODE
      LIMIT 1
    ];

    if (!budgets.isEmpty()) {
      Monthly_Budget__c budget = budgets[0];
      summary.budgetAmount = nvl(budget.Budget_Amount__c);
      summary.rolloverAmount = nvl(budget.Rollover_In__c);
      summary.committedAmount = nvl(budget.Committed__c);
      summary.availableAmount = nvl(budget.Available__c);
    } else {
      summary.budgetAmount = 0;
      summary.committedAmount = 0;
      summary.rolloverAmount = previousAvailable(normalizedStart);
      summary.availableAmount = summary.rolloverAmount;
    }

    summary.hasBudget =
      summary.budgetAmount != 0 ||
      summary.rolloverAmount != 0;

    for (Expense_Installment__c installment : [
      SELECT
        Amount__c,
        Installment_Number__c,
        Expense__c,
        Expense__r.Description__c,
        Expense__r.Purchase_Date__c,
        Expense__r.Total_Amount__c,
        Expense__r.Number_Of_Installments__c,
        Expense__r.Category__c,
        Expense__r.Person__c
      FROM Expense_Installment__c
      WHERE Month_Start__c = :normalizedStart
      WITH USER_MODE
      ORDER BY Expense__r.Purchase_Date__c DESC
    ]) {
      ExpenseItem item = new ExpenseItem();
      item.id = installment.Expense__c;
      item.description = installment.Expense__r.Description__c;
      item.purchaseDate = installment.Expense__r.Purchase_Date__c;
      item.totalAmount = installment.Expense__r.Total_Amount__c;
      item.numberOfInstallments = Integer.valueOf(
        installment.Expense__r.Number_Of_Installments__c
      );
      item.installmentAmount = installment.Amount__c;
      item.category = installment.Expense__r.Category__c;
      item.person = installment.Expense__r.Person__c;
      item.installmentNumber = Integer.valueOf(
        installment.Installment_Number__c
      );
      summary.expenses.add(item);
    }

    Decimal effectiveBudget = summary.budgetAmount + summary.rolloverAmount;
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

  private static Decimal previousAvailable(Date normalizedStart) {
    List<Monthly_Budget__c> previous = [
      SELECT Available__c
      FROM Monthly_Budget__c
      WHERE Month_Start__c < :normalizedStart
      WITH USER_MODE
      ORDER BY Month_Start__c DESC
      LIMIT 1
    ];
    return previous.isEmpty() ? 0 : nvl(previous[0].Available__c);
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

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
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
