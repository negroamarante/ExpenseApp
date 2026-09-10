public with sharing class BudgetController {
  public class MonthSummary {
    @AuraEnabled
    public Date monthStart;
    @AuraEnabled
    public String monthLabel;
    @AuraEnabled
    public Decimal budgetAmount;
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

    MonthSummary summary = new MonthSummary();
    summary.monthStart = normalizedStart;
    summary.monthLabel = formatMonthLabel(normalizedStart);
    summary.expenses = new List<ExpenseItem>();

    Monthly_Budget__c budget = getBudgetRecord(normalizedStart);
    summary.hasBudget = budget != null;
    summary.budgetAmount = budget != null ? budget.Budget_Amount__c : 0;

    Decimal committed = 0;
    List<Expense__c> monthExpenses = [
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
      WHERE Purchase_Date__c <= :monthEnd AND End_Date__c >= :normalizedStart
      WITH USER_MODE
      ORDER BY Purchase_Date__c DESC
    ];
    for (Expense__c exp : monthExpenses) {
      committed += exp.Installment_Amount__c;

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

    summary.committedAmount = committed;
    summary.availableAmount = summary.budgetAmount - committed;
    summary.percentUsed = summary.budgetAmount > 0
      ? (committed / summary.budgetAmount * 100).setScale(0)
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
