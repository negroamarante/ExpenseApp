import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import { deleteRecord } from "lightning/uiRecordApi";
import FORM_FACTOR from "@salesforce/client/formFactor";
import getMonthSummary from "@salesforce/apex/BudgetController.getMonthSummary";
import ExpenseFormModal from "c/expenseFormModal";
import BudgetEditModal from "c/budgetEditModal";

export default class BudgetDashboard extends LightningElement {
  monthStart = this.toDateString(this.startOfMonth(new Date()));
  summary;
  wiredResult;
  isLoading = true;

  get isNotMobile() {
    return FORM_FACTOR !== "Small";
  }

  get hasExpenseList() {
    return !this.isLoading;
  }

  @wire(getMonthSummary, { monthStart: "$monthStart" })
  wiredSummary(result) {
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

  get budgetAmount() {
    return this.summary ? this.summary.budgetAmount : 0;
  }

  get committedAmount() {
    return this.summary ? this.summary.committedAmount : 0;
  }

  get availableAmount() {
    return this.summary ? this.summary.availableAmount : 0;
  }

  get percentUsed() {
    return this.summary ? this.summary.percentUsed : 0;
  }

  get percentAvailable() {
    return this.summary ? Math.max(0, 100 - this.summary.percentUsed) : 100;
  }

  get hasBudget() {
    return this.summary ? this.summary.hasBudget : false;
  }

  get expenses() {
    return this.summary ? this.summary.expenses : [];
  }

  get statusClass() {
    const pct = this.percentAvailable;
    if (pct <= 10) {
      return "status-tile status-red";
    }
    if (pct <= 30) {
      return "status-tile status-yellow";
    }
    return "status-tile status-green";
  }

  get availableIcon() {
    const pct = this.percentAvailable;
    if (pct <= 10) {
      return "🔴";
    }
    if (pct <= 30) {
      return "🟡";
    }
    return "🟢";
  }

  handlePrevMonth() {
    this.shiftMonth(-1);
  }

  handleNextMonth() {
    this.shiftMonth(1);
  }

  shiftMonth(delta) {
    const [year, month] = this.monthStart.split("-").map(Number);
    const date = new Date(year, month - 1 + delta, 1);
    this.monthStart = this.toDateString(date);
  }

  async handleAddExpense() {
    const result = await ExpenseFormModal.open({
      size: "small",
      description: "Nuevo consumo"
    });
    if (result === "success") {
      this.refresh();
    }
  }

  async handleEditExpense(event) {
    const result = await ExpenseFormModal.open({
      size: "small",
      description: "Editar consumo",
      expenseId: event.detail.expenseId
    });
    if (result === "success") {
      this.refresh();
    }
  }

  async handleDeleteExpense(event) {
    const expenseId = event.detail.expenseId;
    const confirmed = await LightningConfirm.open({
      message: "¿Eliminar este consumo? Esta acción no se puede deshacer.",
      variant: "headerless",
      label: "Confirmar eliminación"
    });
    if (!confirmed) {
      return;
    }
    try {
      await deleteRecord(expenseId);
      this.refresh();
    } catch (error) {
      if (error?.body?.errorCode === "INSUFFICIENT_ACCESS_OR_READONLY") {
        this.notifyError({
          body: { message: "No tenés permiso para eliminar este consumo." }
        });
      } else {
        this.notifyError(error);
      }
    }
  }

  async handleEditBudget() {
    const result = await BudgetEditModal.open({
      size: "small",
      description: "Editar presupuesto",
      monthStart: this.monthStart,
      currentAmount: this.hasBudget ? this.budgetAmount : null
    });
    if (result === "success") {
      this.refresh();
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
      error && error.body && error.body.message
        ? error.body.message
        : "Ocurrió un error inesperado.";
    this.dispatchEvent(
      new ShowToastEvent({ title: "Error", message, variant: "error" })
    );
  }
}
