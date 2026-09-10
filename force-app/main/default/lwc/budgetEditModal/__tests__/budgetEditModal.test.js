import { createElement } from "lwc";
import BudgetEditModal from "c/budgetEditModal";
import saveBudget from "@salesforce/apex/BudgetController.saveBudget";
import getPreviousMonthBudgetAmount from "@salesforce/apex/BudgetController.getPreviousMonthBudgetAmount";

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
  "@salesforce/apex/BudgetController.saveBudget",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/BudgetController.getPreviousMonthBudgetAmount",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe("c-budget-edit-modal", () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("uses the current amount without fetching the previous month when one is provided", async () => {
    const element = createElement("c-budget-edit-modal", {
      is: BudgetEditModal
    });
    element.monthStart = "2026-09-01";
    element.currentAmount = 500;
    document.body.appendChild(element);
    await flushPromises();

    expect(getPreviousMonthBudgetAmount).not.toHaveBeenCalled();
    const input = element.shadowRoot.querySelector("lightning-input");
    expect(input.value).toBe(500);
  });

  it("offers to copy the previous month's amount when there is no current amount", async () => {
    getPreviousMonthBudgetAmount.mockResolvedValue(1200);

    const element = createElement("c-budget-edit-modal", {
      is: BudgetEditModal
    });
    element.monthStart = "2026-09-01";
    element.currentAmount = null;
    document.body.appendChild(element);
    await flushPromises();

    expect(getPreviousMonthBudgetAmount).toHaveBeenCalledWith({
      monthStart: "2026-09-01"
    });

    const copyButton = element.shadowRoot.querySelector(".copy-btn");
    expect(copyButton).not.toBeNull();

    copyButton.click();
    await flushPromises();

    const input = element.shadowRoot.querySelector("lightning-input");
    expect(input.value).toBe(1200);
  });

  it("saves the budget and closes with success", async () => {
    saveBudget.mockResolvedValue();

    const element = createElement("c-budget-edit-modal", {
      is: BudgetEditModal
    });
    element.monthStart = "2026-09-01";
    element.currentAmount = 800;
    document.body.appendChild(element);
    await flushPromises();

    const input = element.shadowRoot.querySelector("lightning-input");
    input.checkValidity = jest.fn().mockReturnValue(true);
    input.reportValidity = jest.fn();
    input.value = 900;
    input.dispatchEvent(new CustomEvent("change", { detail: { value: 900 } }));

    const closeHandler = jest.fn();
    element.addEventListener("__close", closeHandler);

    element.shadowRoot.querySelectorAll("lightning-button")[1].click();
    await flushPromises();

    expect(saveBudget).toHaveBeenCalledWith({
      monthStart: "2026-09-01",
      amount: 900
    });
    expect(closeHandler.mock.calls[0][0].detail).toBe("success");
  });

  it("shows an error toast when saving fails", async () => {
    saveBudget.mockRejectedValue({ body: { message: "No se pudo guardar." } });

    const element = createElement("c-budget-edit-modal", {
      is: BudgetEditModal
    });
    element.monthStart = "2026-09-01";
    element.currentAmount = 800;
    document.body.appendChild(element);
    await flushPromises();

    const input = element.shadowRoot.querySelector("lightning-input");
    input.checkValidity = jest.fn().mockReturnValue(true);
    input.reportValidity = jest.fn();

    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);
    const closeHandler = jest.fn();
    element.addEventListener("__close", closeHandler);

    element.shadowRoot.querySelectorAll("lightning-button")[1].click();
    await flushPromises();

    expect(toastHandler).toHaveBeenCalledTimes(1);
    expect(toastHandler.mock.calls[0][0].detail.message).toBe(
      "No se pudo guardar."
    );
    expect(closeHandler).not.toHaveBeenCalled();
  });
});
