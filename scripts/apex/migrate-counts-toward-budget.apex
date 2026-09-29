// One-time (idempotent) data fix for the Counts_Toward_Budget__c /
// Counts_Toward_Spending__c rollout.
//
// A field's <defaultValue> only applies when a NEW record is created; it is
// never backfilled onto rows that already existed before the field was
// deployed. Before this feature, every Expense__c implicitly counted toward
// the credit-limit budget, so any legacy expense left with both flags false
// must be marked Counts_Toward_Budget__c = true or it silently disappears
// from BudgetController's list and from Committed__c/Rollover_In__c
// recalculation.
//
// Safe to run repeatedly: once legacy rows are fixed, the WHERE clause only
// matches rows with both flags false, which no longer exist after the first
// run (new spending-only expenses always set Counts_Toward_Spending__c).
List<Expense__c> legacy = [
  SELECT Id
  FROM Expense__c
  WHERE Counts_Toward_Budget__c = false AND Counts_Toward_Spending__c = false
];

if (!legacy.isEmpty()) {
  for (Expense__c expense : legacy) {
    expense.Counts_Toward_Budget__c = true;
  }
  update legacy;
}

Integer recalculated = ExpenseInstallmentService.backfillAll();
System.debug(
  'Counts_Toward_Budget__c migration: fixed ' +
  legacy.size() +
  ' legacy expense(s); recalculated installments for ' +
  recalculated +
  ' expense(s).'
);
