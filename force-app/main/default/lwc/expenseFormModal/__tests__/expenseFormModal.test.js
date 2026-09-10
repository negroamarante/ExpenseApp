import { createElement } from "lwc";
import ExpenseFormModal from "c/expenseFormModal";
import { getRecord, createRecord, updateRecord } from "lightning/uiRecordApi";
import scanReceipt from "@salesforce/apex/ReceiptScanController.scanReceipt";
import attachReceipt from "@salesforce/apex/ReceiptScanController.attachReceipt";

jest.mock(
  "lightning/modal",
  () => {
    const { LightningElement } = require("lwc");
    class LightningModal extends LightningElement {
      close(result) {
        this.dispatchEvent(new CustomEvent("__close", { detail: result }));
      }
    }
    return { __esModule: true, default: LightningModal };
  },
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/ReceiptScanController.scanReceipt",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/ReceiptScanController.attachReceipt",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function fillField(element, fieldName, value) {
  const el = element.shadowRoot.querySelector(`[data-field="${fieldName}"]`);
  el.checkValidity = jest.fn().mockReturnValue(true);
  el.reportValidity = jest.fn();
  el.value = value;
  return el;
}

function mockImagePipeline() {
  const originals = {
    Image: global.Image,
    FileReader: global.FileReader,
    getContext: HTMLCanvasElement.prototype.getContext,
    toDataURL: HTMLCanvasElement.prototype.toDataURL
  };

  global.Image = class {
    set src(_value) {
      if (this.onload) {
        this.onload();
      }
    }
    get width() {
      return 100;
    }
    get height() {
      return 100;
    }
  };
  HTMLCanvasElement.prototype.getContext = () => ({ drawImage: jest.fn() });
  HTMLCanvasElement.prototype.toDataURL = () => "data:image/jpeg;base64,abc123";
  global.FileReader = class {
    readAsDataURL() {
      this.result = "data:image/jpeg;base64,rawbase64";
      if (this.onload) {
        this.onload();
      }
    }
  };

  return () => {
    global.Image = originals.Image;
    global.FileReader = originals.FileReader;
    HTMLCanvasElement.prototype.getContext = originals.getContext;
    HTMLCanvasElement.prototype.toDataURL = originals.toDataURL;
  };
}

describe("c-expense-form-modal", () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("creates a new expense with the values entered by the user", async () => {
    createRecord.mockResolvedValue({ id: "a01000000000001" });

    const element = createElement("c-expense-form-modal", {
      is: ExpenseFormModal
    });
    document.body.appendChild(element);
    await flushPromises();

    fillField(element, "description", "Supermercado");
    fillField(element, "purchaseDate", "2026-09-01");
    fillField(element, "totalAmount", "1000");
    fillField(element, "numberOfInstallments", "1");
    fillField(element, "category", "Comida");
    fillField(element, "person", "Diego");

    const closeHandler = jest.fn();
    element.addEventListener("__close", closeHandler);

    element.shadowRoot
      .querySelectorAll("lightning-button")[1]
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(createRecord).toHaveBeenCalledTimes(1);
    const callArg = createRecord.mock.calls[0][0];
    expect(callArg.apiName).toBe("Expense__c");
    expect(callArg.fields).toMatchObject({
      Description__c: "Supermercado",
      Purchase_Date__c: "2026-09-01",
      Total_Amount__c: 1000,
      Number_Of_Installments__c: "1",
      Category__c: "Comida",
      Person__c: "Diego"
    });
    expect(closeHandler.mock.calls[0][0].detail).toBe("success");
  });

  it("does not save when a field is invalid", async () => {
    const element = createElement("c-expense-form-modal", {
      is: ExpenseFormModal
    });
    document.body.appendChild(element);
    await flushPromises();

    const descriptionEl = fillField(element, "description", "");
    descriptionEl.checkValidity = jest.fn().mockReturnValue(false);
    fillField(element, "purchaseDate", "2026-09-01");
    fillField(element, "totalAmount", "1000");
    fillField(element, "numberOfInstallments", "1");
    fillField(element, "category", "Comida");
    fillField(element, "person", "Diego");

    const closeHandler = jest.fn();
    element.addEventListener("__close", closeHandler);

    element.shadowRoot
      .querySelectorAll("lightning-button")[1]
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(createRecord).not.toHaveBeenCalled();
    expect(closeHandler).not.toHaveBeenCalled();
  });

  it("loads an existing expense through the record wire and updates it on save", async () => {
    updateRecord.mockResolvedValue({});

    const element = createElement("c-expense-form-modal", {
      is: ExpenseFormModal
    });
    element.expenseId = "a01000000000002";
    document.body.appendChild(element);
    await flushPromises();

    getRecord.emit({
      fields: {
        Description__c: { value: "Alquiler" },
        Purchase_Date__c: { value: "2026-08-01" },
        Total_Amount__c: { value: 2000 },
        Number_Of_Installments__c: { value: "1" },
        Category__c: { value: "Vivienda" },
        Person__c: { value: "Diego" }
      }
    });
    await flushPromises();

    const descriptionEl = element.shadowRoot.querySelector(
      '[data-field="description"]'
    );
    expect(descriptionEl.value).toBe("Alquiler");

    element.shadowRoot.querySelectorAll("[data-field]").forEach((el) => {
      el.checkValidity = jest.fn().mockReturnValue(true);
      el.reportValidity = jest.fn();
    });

    const closeHandler = jest.fn();
    element.addEventListener("__close", closeHandler);

    element.shadowRoot
      .querySelectorAll("lightning-button")[1]
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(updateRecord).toHaveBeenCalledTimes(1);
    expect(updateRecord.mock.calls[0][0].fields).toMatchObject({
      Id: "a01000000000002",
      Description__c: "Alquiler"
    });
    expect(closeHandler.mock.calls[0][0].detail).toBe("success");
  });

  it("scans a receipt and attaches it to the expense after saving", async () => {
    const restoreImagePipeline = mockImagePipeline();

    scanReceipt.mockResolvedValue({
      description: "Farmacia",
      purchaseDate: "2026-09-05",
      totalAmount: 250,
      category: "Salud",
      person: "Diego"
    });
    createRecord.mockResolvedValue({ id: "a01000000000003" });
    attachReceipt.mockResolvedValue();

    const element = createElement("c-expense-form-modal", {
      is: ExpenseFormModal
    });
    document.body.appendChild(element);
    await flushPromises();

    const fakeFile = new File(["fake"], "ticket.jpg", {
      type: "image/jpeg"
    });
    const receiptInput = element.shadowRoot.querySelector(".receipt-input");
    Object.defineProperty(receiptInput, "files", { value: [fakeFile] });
    receiptInput.dispatchEvent(new CustomEvent("change"));
    await flushPromises();

    expect(scanReceipt).toHaveBeenCalledWith({
      base64Image: "abc123",
      mimeType: "image/jpeg",
      categoryOptions: [],
      personOptions: []
    });

    const descriptionEl = element.shadowRoot.querySelector(
      '[data-field="description"]'
    );
    expect(descriptionEl.value).toBe("Farmacia");

    element.shadowRoot.querySelectorAll("[data-field]").forEach((el) => {
      el.checkValidity = jest.fn().mockReturnValue(true);
      el.reportValidity = jest.fn();
    });

    element.shadowRoot
      .querySelectorAll("lightning-button")[1]
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(attachReceipt).toHaveBeenCalledWith({
      expenseId: "a01000000000003",
      base64Data: "abc123",
      fileName: "ticket.jpg",
      mimeType: "image/jpeg"
    });

    restoreImagePipeline();
  });

  it("clears the selected receipt when the scan fails validation", async () => {
    const restoreImagePipeline = mockImagePipeline();

    scanReceipt.mockRejectedValue({
      body: {
        message:
          "No se pudo leer del ticket: monto. Completá esos campos a mano."
      }
    });

    const element = createElement("c-expense-form-modal", {
      is: ExpenseFormModal
    });
    document.body.appendChild(element);
    await flushPromises();

    const fakeFile = new File(["fake"], "ticket.jpg", {
      type: "image/jpeg"
    });
    const receiptInput = element.shadowRoot.querySelector(".receipt-input");
    Object.defineProperty(receiptInput, "files", { value: [fakeFile] });

    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);

    receiptInput.dispatchEvent(new CustomEvent("change"));
    await flushPromises();

    expect(toastHandler.mock.calls[0][0].detail.message).toBe(
      "No se pudo leer del ticket: monto. Completá esos campos a mano."
    );
    expect(element.shadowRoot.querySelector(".receipt-file-name")).toBeNull();
    expect(receiptInput.value).toBe("");

    createRecord.mockResolvedValue({ id: "a01000000000004" });
    fillField(element, "description", "Supermercado");
    fillField(element, "purchaseDate", "2026-09-01");
    fillField(element, "totalAmount", "1000");
    fillField(element, "numberOfInstallments", "1");
    fillField(element, "category", "Comida");
    fillField(element, "person", "Diego");

    element.shadowRoot
      .querySelectorAll("lightning-button")[1]
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(attachReceipt).not.toHaveBeenCalled();

    restoreImagePipeline();
  });
});
