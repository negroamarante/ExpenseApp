trigger MonthlyBudgetTrigger on Monthly_Budget__c(
  after insert,
  after update,
  after delete
) {
  if (Trigger.isDelete) {
    ExpenseInstallmentService.handleBudgetDelete(Trigger.old);
  } else {
    ExpenseInstallmentService.handleBudgetChange(
      Trigger.new,
      Trigger.isInsert ? null : Trigger.oldMap
    );
  }
}
