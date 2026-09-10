import { api, wire } from "lwc";
import LightningModal from "lightning/modal";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import { getRecord, createRecord, updateRecord } from "lightning/uiRecordApi";
import scanReceipt from "@salesforce/apex/ReceiptScanController.scanReceipt";
import attachReceipt from "@salesforce/apex/ReceiptScanController.attachReceipt";
import EXPENSE_OBJECT from "@salesforce/schema/Expense__c";
import ID_FIELD from "@salesforce/schema/Expense__c.Id";
import DESCRIPTION_FIELD from "@salesforce/schema/Expense__c.Description__c";
import PURCHASE_DATE_FIELD from "@salesforce/schema/Expense__c.Purchase_Date__c";
import TOTAL_AMOUNT_FIELD from "@salesforce/schema/Expense__c.Total_Amount__c";
import CATEGORY_FIELD from "@salesforce/schema/Expense__c.Category__c";
import PERSON_FIELD from "@salesforce/schema/Expense__c.Person__c";
import INSTALLMENTS_FIELD from "@salesforce/schema/Expense__c.Number_Of_Installments__c";

const MONTH_NAMES = [
  "ene",
  "feb",
  "mar",
  "abr",
  "may",
  "jun",
  "jul",
  "ago",
  "sep",
  "oct",
  "nov",
  "dic"
];

export default class ExpenseFormModal extends LightningModal {
  @api expenseId;

  expenseDescription = "";
  purchaseDate;
  totalAmount;
  numberOfInstallments = "1";
  category;
  person;
  isSaving = false;
  isLoading = false;
  isScanning = false;

  objectInfo;
  categoryOptions = [];
  personOptions = [];
  installmentsOptions = [];

  receiptBase64;
  receiptMimeType;
  receiptFileName;

  connectedCallback() {
    this.purchaseDate = this.todayIso();
    if (this.expenseId) {
      this.isLoading = true;
    }
  }

  renderedCallback() {
    const receiptInput = this.template.querySelector("#receipt-input");
    if (receiptInput && !receiptInput.hasAttribute("capture")) {
      receiptInput.setAttribute("capture", "environment");
    }
  }

  @wire(getRecord, {
    recordId: "$expenseId",
    fields: [
      DESCRIPTION_FIELD,
      PURCHASE_DATE_FIELD,
      TOTAL_AMOUNT_FIELD,
      INSTALLMENTS_FIELD,
      CATEGORY_FIELD,
      PERSON_FIELD
    ]
  })
  wiredExpense({ data, error }) {
    if (data) {
      this.expenseDescription = data.fields.Description__c.value;
      this.purchaseDate = data.fields.Purchase_Date__c.value;
      this.totalAmount = data.fields.Total_Amount__c.value;
      this.numberOfInstallments = data.fields.Number_Of_Installments__c.value;
      this.category = data.fields.Category__c.value;
      this.person = data.fields.Person__c.value;
      this.isLoading = false;
    } else if (error) {
      this.notifyError(error);
      this.isLoading = false;
    }
  }

  @wire(getObjectInfo, { objectApiName: EXPENSE_OBJECT })
  objectInfoResult({ data }) {
    this.objectInfo = data;
  }

  @wire(getPicklistValues, {
    recordTypeId: "$objectInfo.defaultRecordTypeId",
    fieldApiName: CATEGORY_FIELD
  })
  categoryPicklist({ data }) {
    if (data) {
      this.categoryOptions = data.values.map((v) => ({
        label: v.label,
        value: v.value
      }));
    }
  }

  @wire(getPicklistValues, {
    recordTypeId: "$objectInfo.defaultRecordTypeId",
    fieldApiName: PERSON_FIELD
  })
  personPicklist({ data }) {
    if (data) {
      this.personOptions = data.values.map((v) => ({
        label: v.label,
        value: v.value
      }));
    }
  }

  @wire(getPicklistValues, {
    recordTypeId: "$objectInfo.defaultRecordTypeId",
    fieldApiName: INSTALLMENTS_FIELD
  })
  installmentsPicklist({ data }) {
    if (data) {
      this.installmentsOptions = data.values.map((v) => ({
        label: v.label,
        value: v.value
      }));
    }
  }

  get isEdit() {
    return !!this.expenseId;
  }

  get modalTitle() {
    return this.isEdit ? "Editar consumo" : "Nuevo consumo";
  }

  get installmentPreview() {
    const amount = Number(this.totalAmount);
    const installments = Number(this.numberOfInstallments);
    if (!amount || !installments || installments < 1) {
      return null;
    }
    return amount / installments;
  }

  get affectedMonthsLabel() {
    if (!this.purchaseDate || !this.numberOfInstallments) {
      return "";
    }
    const [y, m] = this.purchaseDate.split("-").map(Number);
    const start = new Date(y, m - 1, 1);
    const end = new Date(y, m - 1 + (Number(this.numberOfInstallments) - 1), 1);
    const startLabel = `${MONTH_NAMES[start.getMonth()]} ${start.getFullYear()}`;
    const endLabel = `${MONTH_NAMES[end.getMonth()]} ${end.getFullYear()}`;
    return Number(this.numberOfInstallments) > 1
      ? `${startLabel} → ${endLabel}`
      : startLabel;
  }

  handleDescriptionChange(event) {
    this.expenseDescription = event.target.value;
  }

  handlePurchaseDateChange(event) {
    this.purchaseDate = event.target.value;
  }

  handleTotalAmountChange(event) {
    this.totalAmount = event.target.value;
  }

  handleInstallmentsChange(event) {
    this.numberOfInstallments = event.detail.value;
  }

  handleCategoryChange(event) {
    this.category = event.detail.value;
  }

  handlePersonChange(event) {
    this.person = event.detail.value;
  }

  handleCancel() {
    this.close("cancel");
  }

  async handleReceiptFileChange(event) {
    const inputEl = event.target;
    const file = inputEl.files[0];
    if (!file) {
      return;
    }
    this.isScanning = true;
    try {
      const { base64, mimeType } = await this.compressImage(file);
      this.receiptBase64 = base64;
      this.receiptMimeType = mimeType;
      this.receiptFileName = file.name;

      const result = await scanReceipt({
        base64Image: base64,
        mimeType,
        categoryOptions: this.categoryOptions.map((option) => option.value),
        personOptions: this.personOptions.map((option) => option.value)
      });

      if (result.description) {
        this.expenseDescription = result.description;
      }
      if (result.purchaseDate) {
        this.purchaseDate = result.purchaseDate;
      }
      if (result.totalAmount) {
        this.totalAmount = result.totalAmount;
      }
      if (result.category) {
        this.category = result.category;
      }
      if (result.person) {
        this.person = result.person;
      }
    } catch (error) {
      this.notifyError(error);
      this.receiptBase64 = undefined;
      this.receiptMimeType = undefined;
      this.receiptFileName = undefined;
      inputEl.value = null;
    } finally {
      this.isScanning = false;
    }
  }

  compressImage(file) {
    const MAX_DIMENSION = 1600;
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onerror = () => reject(reader.error);
      reader.onload = () => {
        const img = new Image();
        img.onerror = reject;
        img.onload = () => {
          let { width, height } = img;
          if (width > MAX_DIMENSION || height > MAX_DIMENSION) {
            const scale = MAX_DIMENSION / Math.max(width, height);
            width = Math.round(width * scale);
            height = Math.round(height * scale);
          }
          const canvas = document.createElement("canvas");
          canvas.width = width;
          canvas.height = height;
          canvas.getContext("2d").drawImage(img, 0, 0, width, height);
          const dataUrl = canvas.toDataURL("image/jpeg", 0.7);
          resolve({ base64: dataUrl.split(",")[1], mimeType: "image/jpeg" });
        };
        img.src = reader.result;
      };
      reader.readAsDataURL(file);
    });
  }

  async handleSave() {
    const fieldEls = [...this.template.querySelectorAll("[data-field]")];
    let allValid = true;
    const values = {};
    fieldEls.forEach((el) => {
      el.reportValidity();
      allValid = el.checkValidity() && allValid;
      values[el.dataset.field] = el.value;
    });
    if (!allValid) {
      return;
    }

    this.isSaving = true;
    const fields = {
      [DESCRIPTION_FIELD.fieldApiName]: values.description,
      [PURCHASE_DATE_FIELD.fieldApiName]: values.purchaseDate,
      [TOTAL_AMOUNT_FIELD.fieldApiName]: Number(values.totalAmount),
      [INSTALLMENTS_FIELD.fieldApiName]: values.numberOfInstallments,
      [CATEGORY_FIELD.fieldApiName]: values.category || null,
      [PERSON_FIELD.fieldApiName]: values.person
    };
    try {
      let savedExpenseId = this.expenseId;
      if (this.isEdit) {
        fields[ID_FIELD.fieldApiName] = this.expenseId;
        await updateRecord({ fields });
      } else {
        const created = await createRecord({
          apiName: EXPENSE_OBJECT.objectApiName,
          fields
        });
        savedExpenseId = created.id;
      }
      if (this.receiptBase64) {
        await attachReceipt({
          expenseId: savedExpenseId,
          base64Data: this.receiptBase64,
          fileName: this.receiptFileName,
          mimeType: this.receiptMimeType
        });
      }
      this.close("success");
    } catch (error) {
      this.notifyError(error);
    } finally {
      this.isSaving = false;
    }
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

  todayIso() {
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
  }
}
