import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { deleteRecord } from "lightning/uiRecordApi";
import LightningConfirm from "lightning/confirm";
import getMonthSpending from "@salesforce/apex/SpendingController.getMonthSpending";
import ExpenseFormModal from "c/expenseFormModal";

export default class SpendingDashboard extends LightningElement {
  monthStart = this.toDateString(this.startOfMonth(new Date()));
  summary;
  wiredResult;
  isLoading = true;

  @wire(getMonthSpending, { monthStart: "$monthStart" })
  wiredSpending(result) {
    this.wiredResult = result;
    this.isLoading = false;
    if (result.data) {
      this.summary = result.data;
    } else if (result.error) {
      this.notifyError(result.error);
    }
  }

  startOfMonth(date) {
    return new Date(date.getFullYear(), date.getMonth(), 1);
  }

  toDateString(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, "0");
    return `${year}-${month}-01`;
  }

  get monthLabel() {
    return this.summary ? this.summary.monthLabel.toUpperCase() : "";
  }

  get totalSpent() {
    return this.summary ? this.summary.totalSpent : 0;
  }

  get expenses() {
    return this.summary ? this.summary.expenses : [];
  }

  get hasExpenses() {
    return this.expenses.length > 0;
  }

  get displayItems() {
    return this.expenses.map((exp) => ({
      ...exp,
      methodLabel: exp.paymentMethod || "Sin medio",
      dualLabel: exp.countsTowardBudget ? "También en límite cupo" : null,
      installmentLabel:
        exp.numberOfInstallments > 1
          ? `Cuota ${exp.installmentNumber}/${exp.numberOfInstallments}`
          : "Pago único",
      amountToShow:
        exp.numberOfInstallments > 1 ? exp.installmentAmount : exp.totalAmount
    }));
  }

  get currentMonthStart() {
    return this.toDateString(this.startOfMonth(new Date()));
  }

  get showCurrentMonthButton() {
    return this.monthStart !== this.currentMonthStart;
  }

  handlePrevMonth() {
    const date = new Date(this.monthStart + "T00:00:00");
    date.setMonth(date.getMonth() - 1);
    this.goToMonth(this.toDateString(this.startOfMonth(date)));
  }

  handleNextMonth() {
    const date = new Date(this.monthStart + "T00:00:00");
    date.setMonth(date.getMonth() + 1);
    this.goToMonth(this.toDateString(this.startOfMonth(date)));
  }

  handleCurrentMonth() {
    this.goToMonth(this.currentMonthStart);
  }

  goToMonth(monthStart) {
    this.isLoading = true;
    this.monthStart = monthStart;
  }

  async handleAddExpense() {
    const result = await ExpenseFormModal.open({
      size: "small",
      description: "Nuevo gasto",
      mode: "spending"
    });
    if (result === "success") {
      this.refresh();
    }
  }

  async handleEditExpense(event) {
    const expenseId = event.currentTarget.dataset.id;
    const result = await ExpenseFormModal.open({
      size: "small",
      description: "Editar gasto",
      mode: "spending",
      expenseId
    });
    if (result === "success") {
      this.refresh();
    }
  }

  async handleDelete(event) {
    event.stopPropagation();
    const expenseId = event.currentTarget.dataset.id;
    const confirmed = await LightningConfirm.open({
      message: "¿Borrar este gasto del control?",
      label: "Confirmar",
      theme: "warning"
    });
    if (!confirmed) {
      return;
    }
    try {
      await deleteRecord(expenseId);
      this.refresh();
    } catch (error) {
      this.notifyError(error);
    }
  }

  refresh() {
    this.isLoading = true;
    refreshApex(this.wiredResult).finally(() => {
      this.isLoading = false;
    });
  }

  notifyError(error) {
    const message =
      error?.body?.message || error?.message || "Error inesperado";
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Error",
        message,
        variant: "error"
      })
    );
  }
}
