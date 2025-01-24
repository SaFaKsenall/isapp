import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_credit_card/flutter_credit_card.dart';

class CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;

    if (newValue.selection.baseOffset == 0) {
      return newValue;
    }

    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex % 4 == 0 && nonZeroIndex != text.length) {
        buffer.write(' ');
      }
    }

    var string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(
        offset: string.length,
      ),
    );
  }
}

class iyzicopayment extends StatefulWidget {
  @override
  _iyzicopaymentState createState() => _iyzicopaymentState();
}

class _iyzicopaymentState extends State<iyzicopayment>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _expiryMonthController = TextEditingController();
  final _expiryYearController = TextEditingController();
  final _cvvController = TextEditingController();
  final _cardHolderController = TextEditingController();
  bool _isLoading = false;
  bool _showSuccess = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final String successAnimationUrl =
      'https://assets6.lottiefiles.com/packages/lf20_s2lryxtd.json'; // Success check mark animation
  // İyzico API bilgileri
  static const String apiKey = "your_api_key";
  static const String secretKey = "your_secret_key";
  static const String baseUrl = "https://sandbox-api.iyzipay.com";

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();

    // Kart numarası değişikliklerini dinle
    _cardNumberController.addListener(() {
      setState(() {});
    });
  }

  String _generateAuthString() {
    var time = DateTime.now().millisecondsSinceEpoch.toString();
    var randomString = DateTime.now().microsecondsSinceEpoch.toString();
    var authString = apiKey + randomString + secretKey + time;
    var bytes = utf8.encode(authString);
    var hash = sha1.convert(bytes);
    return base64.encode(hash.bytes);
  }

  Future<void> _initiatePayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Tutarı double'a çevirip string'e dönüştürme
      double amount = double.parse(_amountController.text);
      String formattedAmount = amount.toStringAsFixed(2);

      var paymentRequest = {
        "locale": "tr",
        "conversationId": DateTime.now().millisecondsSinceEpoch.toString(),
        "price": formattedAmount,
        "paidPrice": formattedAmount,
        "currency": "TRY",
        "installment": 1, // String yerine integer kullan
        "paymentChannel": "MOBILE_SDK", // WEB yerine MOBILE_SDK kullan
        "paymentGroup": "PRODUCT",
        "paymentCard": {
          "cardHolderName": _cardHolderController.text.trim(),
          "cardNumber": _cardNumberController.text.replaceAll(" ", ""),
          "expireMonth": _expiryMonthController.text
              .padLeft(2, '0'), // Ay için 2 haneli format
          "expireYear":
              "20${_expiryYearController.text.padLeft(2, '0')}", // Yıl için 4 haneli format
          "cvc": _cvvController.text,
          "registerCard": 0 // String yerine integer kullan
        },
        "buyer": {
          "id": "BY789",
          "name": "John",
          "surname": "Doe",
          "identityNumber": "74300864791",
          "email": "email@email.com",
          "registrationAddress":
              "Nidakule Göztepe, Merdivenköy Mah. Bora Sok. No:1",
          "city": "Istanbul",
          "country": "Turkey",
          "ip": "85.34.78.112"
        }
      };

      // API isteğini güvenli HTTPS ile yap
      final response = await http.post(
        Uri.parse('$baseUrl/payment/auth'),
        headers: {
          'Authorization': _generateAuthString(),
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(paymentRequest),
      );

      final responseData = json.decode(response.body);

      setState(() {
        _isLoading = false;
        _showSuccess = responseData['status'] == 'success';
      });

      if (_showSuccess) {
        // Başarılı ödeme animasyonunu göster
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Lottie.network(
                  'lottie/1735243972999.json',
                  width: 150,
                  height: 150,
                  repeat: false,
                ),
                SizedBox(height: 20),
                Text(
                  'Ödeme Başarılı!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );

        Future.delayed(Duration(seconds: 2), () {
          Navigator.of(context).pop(); // Dialog'u kapat
          // İsterseniz başka bir sayfaya yönlendirme yapabilirsiniz
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ödeme başarısız: ${responseData['errorMessage']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bir hata oluştu: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          'Para Yatır',
          style: TextStyle(color: Colors.black87),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Üst kısımda animasyon
                Lottie.asset(
                  'lottie/1735243972998.json',
                  height: 150,
                  fit: BoxFit.contain,
                ),

                // Kredi kartı görünümü
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: CreditCardWidget(
                    cardNumber: _cardNumberController.text,
                    expiryDate:
                        '${_expiryMonthController.text}/${_expiryYearController.text}',
                    cardHolderName: _cardHolderController.text,
                    cvvCode: _cvvController.text,
                    showBackView: false,
                    onCreditCardWidgetChange: (brand) {},
                  ),
                ),

                // Tutar girişi
                Container(
                  margin: EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                      labelText: 'Yatırmak istediğiniz miktar',
                      prefixText: '₺ ',
                      prefixIcon: Icon(Icons.attach_money),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return 'Lütfen bir miktar girin';
                      final amount = double.tryParse(value);
                      if (amount == null || amount <= 0)
                        return 'Geçerli bir miktar girin';
                      return null;
                    },
                  ),
                ),

                // Kart bilgileri
                Container(
                  margin: EdgeInsets.symmetric(vertical: 8),
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _cardHolderController,
                        decoration: InputDecoration(
                          labelText: 'Kart Sahibinin Adı Soyadı',
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (value) => value?.isEmpty ?? true
                            ? 'Bu alan zorunludur'
                            : null,
                      ),
                      SizedBox(height: 16),
                      TextFormField(
                        controller: _cardNumberController,
                        decoration: InputDecoration(
                          labelText: 'Kart Numarası',
                          prefixIcon: Icon(Icons.credit_card),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(16),
                          CardNumberFormatter(),
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty)
                            return 'Kart numarası gerekli';
                          if (value.replaceAll(' ', '').length != 16) {
                            return 'Geçerli bir kart numarası girin';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _expiryMonthController,
                              decoration: InputDecoration(
                                labelText: 'Ay',
                                prefixIcon: Icon(Icons.calendar_today),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(2),
                              ],
                              validator: (value) {
                                if (value == null || value.isEmpty)
                                  return 'Gerekli';
                                final month = int.tryParse(value);
                                if (month == null || month < 1 || month > 12) {
                                  return 'Geçersiz';
                                }
                                return null;
                              },
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _expiryYearController,
                              decoration: InputDecoration(
                                labelText: 'Yıl',
                                prefixIcon: Icon(Icons.calendar_today),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(2),
                              ],
                              validator: (value) =>
                                  value?.isEmpty ?? true ? 'Gerekli' : null,
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _cvvController,
                              decoration: InputDecoration(
                                labelText: 'CVV',
                                prefixIcon: Icon(Icons.security),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                              validator: (value) {
                                if (value == null || value.isEmpty)
                                  return 'Gerekli';
                                if (value.length != 3) return 'Geçersiz';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 24),

                // Ödeme butonu
                AnimatedContainer(
                  duration: Duration(milliseconds: 300),
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _initiatePayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 5,
                    ),
                    child: _isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text(
                            'Ödemeyi Başlat',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _amountController.dispose();
    _cardNumberController.dispose();
    _expiryMonthController.dispose();
    _expiryYearController.dispose();
    _cvvController.dispose();
    _cardHolderController.dispose();
    super.dispose();
  }
}
