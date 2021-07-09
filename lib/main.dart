// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert' show json;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import "package:http/http.dart" as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

// import "package:http/http.dart" as http;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:stripe_payment/stripe_payment.dart';
GoogleSignIn _googleSignIn = GoogleSignIn(
// Optional clientId
// clientId: '479882132969-9i9aqik3jfjd7qhci1nqf0bm2g71rm1u.apps.googleusercontent.com',
  scopes: <String>[
    'email',
    'https://www.googleapis.com/auth/contacts.readonly',
  ],
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(
    MaterialApp(
      title: 'Google Sign In',
      home: SignInDemo(),
    ),
  );
}

class SignInDemo extends StatefulWidget {
  @override
  State createState() => SignInDemoState();
}

class SignInDemoState extends State<SignInDemo> {
  GoogleSignInAccount _currentUser;
  String _contactText = '';


  ///////////
  @override
  void initState() {

    // Firebase.initializeApp().whenComplete(() {
    //   print("completed");
    //   setState(() {});
    // });
    // todo change Publishable key

    StripePayment.setOptions(StripeOptions(publishableKey: "feroiufnuerfnureiufnifir"));

    super.initState();
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount account) {
      setState(() {
        _currentUser = account;
      });
      if (_currentUser != null) {
        _handleGetContact(_currentUser);
      }
    });
    _googleSignIn.signInSilently();
  }

  final HttpsCallable INTENT = FirebaseFunctions.instance.httpsCallable( 'createPaymentIntent');

  Future<void> _handleGetContact(GoogleSignInAccount user) async {
    setState(() {
      _contactText = "Loading contact info...";
    });
    final http.Response response = await http.get(
      Uri.parse('https://people.googleapis.com/v1/people/me/connections'
          '?requestMask.includeField=person.names'),
      headers: await user.authHeaders,
    );
    if (response.statusCode != 200) {
      setState(() {
        _contactText = "People API gave a ${response.statusCode} "
            "response. Check logs for details.";
      });
      print('People API ${response.statusCode} response: ${response.body}');
      return;
    }
    final Map<String, dynamic> data = json.decode(response.body);
    final String namedContact = _pickFirstNamedContact(data);
    setState(() {
      if (namedContact != null) {
        _contactText = "I see you know $namedContact!";
      } else {
        _contactText = "No contacts to display.";
      }
    });
  }

  String _pickFirstNamedContact(Map<String, dynamic> data) {
    final List<dynamic> connections = data['connections'];
    final Map<String, dynamic> contact = connections?.firstWhere(
      (dynamic contact) => contact['names'] != null,
      orElse: () => null,
    );
    if (contact != null) {
      final Map<String, dynamic> name = contact['names'].firstWhere(
        (dynamic name) => name['displayName'] != null,
        orElse: () => null,
      );
      if (name != null) {
        return name['displayName'];
      }
    }
    return null;
  }

  Future<void> _handleSignIn() async {
    try {
      await _googleSignIn.signIn();
    } catch (error) {
      print(error);
    }
  }

  Future<void> _handleSignOut() => _googleSignIn.disconnect();
  void addPaymentDetailsToFirestore() {
    FirebaseFirestore.instance.collection("Users").doc(_currentUser.email).collection("Payments").add({
      "currency":"USD",
      'amount':'100',
    });
  }
  confirmPayment(String sec, PaymentMethod paymentMethod) {
    StripePayment.confirmPaymentIntent(
      PaymentIntent(clientSecret: sec, paymentMethodId: paymentMethod.id),
    ).then((val) {
      addPaymentDetailsToFirestore(); //Function to add Payment details to firestore
      final snackBar = SnackBar(content: Text('Payment Successfull'),);
      Scaffold.of(context).showSnackBar(snackBar);
    });
  }
  Widget _buildBody() {
    GoogleSignInAccount user = _currentUser;
    if (user != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          ListTile(
            leading: GoogleUserCircleAvatar(
              identity: user,
            ),
            title: Text(user.displayName ?? ''),
            subtitle: Text(user.email),
          ),
          const Text("Signed in successfully. as "),
          Text(_contactText),
          ElevatedButton(
            child: const Text('SIGN OUT'),
            onPressed: _handleSignOut,
          ),
          ElevatedButton(
            child: const Text('REFRESH'),
            onPressed: (){
              StripePayment.paymentRequestWithCardForm(CardFormPaymentRequest())
                  .then((paymentMethod) {
                double amount=100*100.0; // multipliying with 100 to change $ to cents
                INTENT.call(<String, dynamic>{'amount': amount,'currency':'usd'}).then((response) {
                  confirmDialog(response.data["client_secret"],paymentMethod); //function for confirmation for payment
                });
              });

            },
          ),
        ],
      );
    } else {
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          const Text("You are not currently signed in."),
          ElevatedButton(
            child: const Text('SIGN IN'),
            onPressed: _handleSignIn,
          ),
        ],
      );
    }
  }
  confirmDialog(String clientSecret,PaymentMethod paymentMethod) {
    var confirm = AlertDialog(
      title: Text("Confirm Payement"),
      content: Container(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              "Make Payment",
              // style: TextStyle(fontSize: 25),
            ),
            Text("Charge amount:\$100")
          ],
        ),
      ),
      actions: <Widget>[
        new RaisedButton(
          child: new Text('CANCEL'),
          onPressed: () {
            Navigator.of(context).pop();
            final snackBar = SnackBar(content: Text('Payment Cancelled'),);
            Scaffold.of(context).showSnackBar(snackBar);
          },
        ),
        new RaisedButton(
          child: new Text('Confirm'),
          onPressed: () {
            Navigator.of(context).pop();
            confirmPayment(clientSecret, paymentMethod); // function to confirm Payment
          },
        ),
      ],
    );
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return confirm;
        });
  }
  @override
  Widget build(BuildContext context) {



    return Scaffold(
        appBar: AppBar(
          title: const Text('Google Sign In'),
        ),
        body: ConstrainedBox(
          constraints: const BoxConstraints.expand(),
          child: _buildBody(),
        ));

  }
}
