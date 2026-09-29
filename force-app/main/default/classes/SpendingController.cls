public with sharing class SpendingController {
  public class MonthSpending {
    @AuraEnabled
    public Date monthStart;
    @AuraEnabled
    public String monthLabel;
    @AuraEnabled
    public Decimal totalSpent;
    @AuraEnabled
    public List<SpendingItem> expenses;
  }

  public class SpendingItem {
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
    public String paymentMethod;
    @AuraEnabled
    public Boolean countsTowardBudget;
    @AuraEnabled
    public Integer installmentNumber;
  }

  @AuraEnabled(cacheable=true)
  public static MonthSpending getMonthSpending(Date monthStart) {
    Date normalizedStart = monthStart.toStartOfMonth();

    MonthSpending summary = new MonthSpending();
    summary.monthStart = normalizedStart;
    summary.monthLabel = formatMonthLabel(normalizedStart);
    summary.expenses = new List<SpendingItem>();
    summary.totalSpent = 0;

    for (Expense_Installment__c line : [
      SELECT
        Amount__c,
        Installment_Number__c,
        Expense__c,
        Expense__r.Description__c,
        Expense__r.Purchase_Date__c,
        Expense__r.Total_Amount__c,
        Expense__r.Number_Of_Installments__c,
        Expense__r.Installment_Amount__c,
        Expense__r.Category__c,
        Expense__r.Person__c,
        Expense__r.Payment_Method__c,
        Expense__r.Counts_Toward_Budget__c
      FROM Expense_Installment__c
      WHERE
        Month_Start__c = :normalizedStart
        AND Expense__r.Counts_Toward_Spending__c = TRUE
      WITH USER_MODE
      ORDER BY Expense__r.Purchase_Date__c DESC, Installment_Number__c ASC
    ]) {
      SpendingItem item = new SpendingItem();
      item.id = line.Expense__c;
      item.description = line.Expense__r.Description__c;
      item.purchaseDate = line.Expense__r.Purchase_Date__c;
      item.totalAmount = nvl(line.Expense__r.Total_Amount__c);
      item.numberOfInstallments = Integer.valueOf(
        line.Expense__r.Number_Of_Installments__c
      );
      item.installmentAmount = nvl(line.Amount__c);
      item.category = line.Expense__r.Category__c;
      item.person = line.Expense__r.Person__c;
      item.paymentMethod = line.Expense__r.Payment_Method__c;
      item.countsTowardBudget = line.Expense__r.Counts_Toward_Budget__c;
      item.installmentNumber = Integer.valueOf(line.Installment_Number__c);
      summary.expenses.add(item);
      summary.totalSpent += item.installmentAmount;
    }

    return summary;
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  private static String formatMonthLabel(Date monthStart) {
    Datetime dt = Datetime.newInstance(
      monthStart.year(),
      monthStart.month(),
      monthStart.day()
    );
    return dt.format('MMMM yyyy');
  }
}
