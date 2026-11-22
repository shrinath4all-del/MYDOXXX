const admin = require("firebase-admin");

admin.initializeApp();

// Razorpay payments for bookings, split 10% app / 90% provider
const razorpay = require("./razorpay");
const route = require("./razorpay_route");
exports.createRazorpayOrder = razorpay.createRazorpayOrder;
exports.verifyRazorpayPayment = razorpay.verifyRazorpayPayment;
exports.razorpayWebhook = razorpay.razorpayWebhook;
exports.setupProviderPayouts = route.setupProviderPayouts;
exports.refreshProviderPayoutStatus = route.refreshProviderPayoutStatus;
exports.settleBookingPayment = route.settleBookingPayment;

// Paid chat recharge (plans from Firestore), refund to the MedCoins wallet
const chatRecharge = require('./chat_recharge');
exports.createChatRechargeOrder = chatRecharge.createChatRechargeOrder;
exports.verifyChatRechargePayment = chatRecharge.verifyChatRechargePayment;
exports.refundUnansweredChatRecharges = chatRecharge.refundUnansweredChatRecharges;

// Care physician agency: duty money shares and auto-absent
const careAgency = require("./care_agency");
exports.onDutyCreated = careAgency.onDutyCreated;
exports.markAbsentDuties = careAgency.markAbsentDuties;

// Prices always come from Firestore, never from the phone
const pricing = require("./pricing");
exports.enforceAppointmentPrice = pricing.enforceAppointmentPrice;
exports.enforceVisitFee = pricing.enforceVisitFee;
exports.enforceDutySplit = pricing.enforceDutySplit;

// "Delete account" for every login: deactivated now, deleted after 30 days
const deleteAccount = require("./delete_account");
exports.requestAccountDeletion = deleteAccount.requestAccountDeletion;
exports.cancelAccountDeletion = deleteAccount.cancelAccountDeletion;
exports.purgeDeletedAccounts = deleteAccount.purgeDeletedAccounts;
