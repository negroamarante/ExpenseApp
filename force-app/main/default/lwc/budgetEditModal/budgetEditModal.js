import { api } from "lwc";
import LightningModal from "lightning/modal";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import saveBudget from "@salesforce/apex/BudgetController.saveBudget";
import getPreviousMonthBudgetAmount from "@salesforce/apex/BudgetController.getPreviousMonthBudgetAmount";

export default class BudgetEditModal extends LightningModal {
  @api monthStart;
  @api currentAmount;

  amount;
  isSaving = false;
  previousAmount;

  connectedCallback() {
    if (this.currentAmount !== null && this.currentAmount !== undefined) {
      this.amount = this.currentAmount;
    } else {
      getPreviousMonthBudgetAmount({ monthStart: this.monthStart })
        .then((value) => {
          this.previousAmount = value;
        })
        .catch(() => {
          this.previousAmount = null;
        });
    }
  }

  get showCopyButton() {
    return (
      (this.amount === undefined || this.amount === null) && this.previousAmount
    );
  }

  handleAmountChange(event) {
    this.amount = event.target.value;
  }

  handleCopyPrevious() {
    this.amount = this.previousAmount;
  }

  handleCancel() {
    this.close("cancel");
  }

  async handleSave() {
    const input = this.template.querySelector("lightning-input");
    input.reportValidity();
    if (!input.checkValidity()) {
      return;
    }

    this.isSaving = true;
    try {
      await saveBudget({
        monthStart: this.monthStart,
        amount: Number(this.amount)
      });
      this.close("success");
    } catch (error) {
      const message =
        error && error.body && error.body.message
          ? error.body.message
          : "No se pudo guardar el presupuesto.";
      this.dispatchEvent(
        new ShowToastEvent({ title: "Error", message, variant: "error" })
      );
    } finally {
      this.isSaving = false;
    }
  }
}
