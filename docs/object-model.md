# Modelo de datos

La compra es un registro, cada cuota es otro, y el mes guarda usado / arrastre / disponible.

## Objetos y relaciones

```mermaid
erDiagram
  Monthly_Budget__c {
    date Month_Start__c
    currency Budget_Amount__c
    currency Committed__c
    currency Rollover_In__c
    currency Available__c
  }

  Expense__c {
    string Description__c
    date Purchase_Date__c
    currency Total_Amount__c
    picklist Number_Of_Installments__c
    currency Installment_Amount__c
    date End_Date__c
  }

  Expense_Installment__c {
    number Installment_Number__c
    currency Amount__c
    date Month_Start__c
  }

  Monthly_Budget__c ||--o{ Expense__c : "Purchases (lookup mes de compra)"
  Expense__c ||--|{ Expense_Installment__c : "Installments (master-detail)"
  Monthly_Budget__c ||--|{ Expense_Installment__c : "Budget_Installments (lookup mes de la cuota)"
```

- `Expense__c.Monthly_Budget__c` apunta al presupuesto del **mes de compra**.
- `Expense_Installment__c` es hijo del gasto (se borra con él) y lookup al presupuesto del **mes que paga esa cuota**.
- `Monthly_Budget__c.Available__c` es fórmula: `Budget_Amount__c + Rollover_In__c - Committed__c`. El arrastre del mes siguiente se escribe en `Rollover_In__c`.

## Ejemplo: 600.000 en 6 cuotas desde septiembre

```mermaid
flowchart LR
  E["Expense<br/>600.000 · 6 cuotas · sep"]
  B9["Budget Sep"]
  B10["Budget Oct"]
  B2["Budget Feb"]

  C1["Cuota 1 · 100.000 · Sep"]
  C2["Cuota 2 · 100.000 · Oct"]
  C6["Cuota 6 · 100.000 · Feb"]

  E -->|lookup compra| B9
  E --> C1
  E --> C2
  E --> C6
  C1 --> B9
  C2 --> B10
  C6 --> B2
```
