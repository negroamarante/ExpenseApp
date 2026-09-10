import { LightningElement, api } from "lwc";

export default class ExpenseList extends LightningElement {
  @api expenses = [];

  get hasExpenses() {
    return this.expenses && this.expenses.length > 0;
  }

  get displayItems() {
    return (this.expenses || []).map((exp) => ({
      ...exp,
      installmentLabel:
        exp.numberOfInstallments > 1
          ? `Cuota ${exp.installmentNumber}/${exp.numberOfInstallments}`
          : "Pago único",
      categoryLabel: exp.category || "Sin categoría"
    }));
  }

  handleEdit(event) {
    const expenseId = event.currentTarget.dataset.id;
    this.dispatchEvent(new CustomEvent("edit", { detail: { expenseId } }));
  }

  handleDelete(event) {
    event.stopPropagation();
    const expenseId = event.currentTarget.dataset.id;
    this.dispatchEvent(new CustomEvent("delete", { detail: { expenseId } }));
  }
}
