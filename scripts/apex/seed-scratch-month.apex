// Seeds sample data for the current month on a scratch org.
// Budget tab: card expenses with installments.
// Spending tab: cash / other card / dual-purpose expenses.
Date monthStart = Date.today().toStartOfMonth();

insert new Monthly_Budget__c(
  Month_Start__c = monthStart,
  Budget_Amount__c = 2500000
);

List<Expense__c> expenses = new List<Expense__c>{
  // --- Presupuesto (tarjeta) ---
  new Expense__c(
    Description__c = 'Notebook (6 cuotas)',
    Purchase_Date__c = monthStart.addDays(2),
    Total_Amount__c = 600000,
    Number_Of_Installments__c = '6',
    Person__c = 'Diego',
    Category__c = 'Hogar',
    Payment_Method__c = 'Tarjeta presupuesto',
    Counts_Toward_Budget__c = true,
    Counts_Toward_Spending__c = false
  ),
  new Expense__c(
    Description__c = 'Supermercado tarjeta',
    Purchase_Date__c = monthStart.addDays(5),
    Total_Amount__c = 180000,
    Number_Of_Installments__c = '1',
    Person__c = 'Emi',
    Category__c = 'Supermercado',
    Payment_Method__c = 'Tarjeta presupuesto',
    Counts_Toward_Budget__c = true,
    Counts_Toward_Spending__c = false
  ),
  new Expense__c(
    Description__c = 'Ropa (3 cuotas)',
    Purchase_Date__c = monthStart.addDays(8),
    Total_Amount__c = 150000,
    Number_Of_Installments__c = '3',
    Person__c = 'Emi',
    Category__c = 'Ropa',
    Payment_Method__c = 'Tarjeta presupuesto',
    Counts_Toward_Budget__c = true,
    Counts_Toward_Spending__c = true
  ),
  // --- Solo control del mes ---
  new Expense__c(
    Description__c = 'Verdulería efectivo',
    Purchase_Date__c = monthStart.addDays(3),
    Total_Amount__c = 22000,
    Number_Of_Installments__c = '1',
    Person__c = 'Diego',
    Category__c = 'Supermercado',
    Payment_Method__c = 'Efectivo',
    Counts_Toward_Budget__c = false,
    Counts_Toward_Spending__c = true
  ),
  new Expense__c(
    Description__c = 'Delivery otra tarjeta',
    Purchase_Date__c = monthStart.addDays(7),
    Total_Amount__c = 18500,
    Number_Of_Installments__c = '1',
    Person__c = 'Emi',
    Category__c = 'Entretenimiento',
    Payment_Method__c = 'Otra tarjeta',
    Counts_Toward_Budget__c = false,
    Counts_Toward_Spending__c = true
  ),
  new Expense__c(
    Description__c = 'Farmacia efectivo',
    Purchase_Date__c = monthStart.addDays(11),
    Total_Amount__c = 9800,
    Number_Of_Installments__c = '1',
    Person__c = 'Diego',
    Category__c = 'Salud',
    Payment_Method__c = 'Efectivo',
    Counts_Toward_Budget__c = false,
    Counts_Toward_Spending__c = true
  )
};
insert expenses;

System.debug(
  'Seeded budget + spending sample for ' +
    String.valueOf(monthStart) +
    '. Expenses: ' +
    expenses.size()
);
