1. Functions
Function			Loại				Chức năng
fn_CalculateChargeableWeight	Scalar			Tính trọng lượng tính cước cần tính cả trọng lượng thể tích
fn_GetOrderTotal		Scalar			Tính tổng tiền của một đơn hàng.
fn_GetAvailableStock		Table-valued		Lấy danh sách lô hàng còn tồn khả dụng  phải loại lô hết hạn/hỏng
fn_GetCustomerTotalPurchases	Scalar			Tính tổng tiền mua hàng của khách, bỏ qua đơn đã hủy.
fn_GetQuoteTotalCost		Scalar			Tính tổng phí vận chuyển và đóng gói của báo giá phải thống nhất công thức với view.

2. Stored Procedures
Stored Procedure		Chức năng chính
sp_UpsertSalesOrder		Thêm hoặc cập nhật đơn hàng từ kênh bán hàng xử lý cả đơn và chi tiết đơn, nhập lại không trùng.
sp_CreateFulfillmentOrder	Tạo đơn xử lý tại kho và cập nhật trạng thái đơn gốc.
sp_AllocateInventoryLot		Phân bổ hàng tồn kho cho đơn hàng, kiểm tra tính hợp lệ và cập nhật tồn kho.
sp_SelectShippingQuote		Chọn báo giá vận chuyển cho kiện hàng.
sp_ProcessReturn		    Xử lý hàng trả lại và nhập kho theo phương án đã chọn không cộng tồn hai lần khi gọi lại
sp_GeneratePickingList		Tạo danh sách lấy hàng và số lượng cần lấy.
sp_CreatePickingBatch		Tạo đợt lấy hàng và gán đơn hàng vào đợt.
sp_VerifyFulfillmentOrder	Kiểm tra số lượng phân bổ và xác nhận lấy hàng.
sp_GeneratePackagingPlan	Đề xuất kế hoạch đóng gói dựa trên trọng lượng và sức chứa bổ sung carton, vật liệu đệm, kích thước, số kiện và bảo vệ hàng dễ vỡ.
sp_UpdateFulfillmentTracking	Cập nhật trạng thái xử lý đơn hàng và đồng bộ trạng thái đơn gốc.
sp_GenerateDeliveryManifest	Tạo bảng kê giao hàng cho kho.
sp_DetectDuplicateOrders	Phát hiện đơn hàng có khả năng trùng lặp để kiểm tra.
sp_GeneratePackageDocuments	Tạo phiếu đóng gói, nhãn vận chuyển, mã vạch và mã QR.
sp_UpdateShipmentDeliveryStatus	Cập nhật theo dõi lô hàng và đồng bộ trạng thái khi giao thành công.
sp_ConsolidateOrders để gộp đơn
sp_ApprovePackagingPlan để duyệt
sp_ConfirmPackage để ghi đóng gói thực tế
sp_GenerateShippingQuotes để tạo/tính lại báo giá
sp_CreateShipment để tạo shipment và gán kiện.
3. Triggers
Trigger	Chức năng kiểm soát
TRG_BatchAssignment_SameWarehouse		    Đảm bảo các đơn trong cùng đợt lấy hàng thuộc cùng một kho.
TRG_ConsolidationAssignment_ValidateGroup	Kiểm tra sự đồng ý của khách hàng và tính nhất quán về kho, khách hàng, địa chỉ.
TRG_PackedAllocation_NotExceedPicked		Không cho đóng gói vượt số lượng đã lấy.
TRG_LotAllocation_ProtectPickedQuantity		Không cho giảm số lượng đã lấy xuống thấp hơn số lượng đã đóng gói.
TRG_FulfillmentStatus_ValidateTransition	Ngăn chuyển trạng thái đơn hàng sai quy trình.
TRG_ShippingQuote_ValidateSelection		    Không cho chọn báo giá hết hạn hoặc dịch vụ vận chuyển không hoạt động.
 Giữ unique index để mỗi kiện chỉ chọn một báo giá.
4. Kiểm thử Triggers
Các trigger được kiểm thử bằng cách cố tình tạo dữ liệu không hợp lệ.
Trường hợp kiểm thử					Kết quả mong đợi
Gán đơn từ kho khác vào cùng đợt lấy hàng.		Từ chối và rollback.
Gộp đơn khi thiếu sự đồng ý hoặc thông tin không khớp.	Từ chối và rollback.
Đóng gói vượt số lượng đã lấy.				Từ chối và rollback.
Giảm số lượng đã lấy thấp hơn số lượng đã đóng gói.	Từ chối và rollback.
Chuyển trạng thái đơn hàng sai quy trình.		Từ chối và rollback.
Chọn báo giá hết hạn hoặc dịch vụ không hoạt động.	Từ chối và rollback.