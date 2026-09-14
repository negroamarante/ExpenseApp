trigger ExpenseTrigger on Expense__c(
  after insert,
  after update,
  after delete,
  after undelete
) {
  if (Trigger.isDelete) {
    ExpenseInstallmentService.handleDelete(Trigger.old);
  } else {
    ExpenseInstallmentService.syncFromTrigger(
      Trigger.new,
      Trigger.isInsert ? null : Trigger.oldMap
    );
  }
}
