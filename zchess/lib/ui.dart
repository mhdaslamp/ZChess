import 'package:flutter/material.dart';

class ChessAppUI extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ChessUIScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ChessUIScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Top half - blank space for chessboard
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.white,
            ),
          ),

          // Bottom half - buttons
          Expanded(
            flex: 1,
            child: Column(   // we can set the color here
              children: [
                // Row with Exit, Comment, Undo, Redo
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      controlButton("Abort"),
                      controlButton("Chat"),
                      controlButton("Undo"),
                      controlButton("Redo"),
                    ],
                  ),
                ),

                // Grid of 12 buttons
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: GridView.count(
                      crossAxisCount: 4,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: [
                        gridButton("Say Who's Turn"),
                        gridButton("Say All Board"),
                        gridButton("Say White Pieces"),
                        gridButton("Say Black Pieces"),
                        gridButton("ReadRow"),
                        gridButton("ReadColumn"),
                        gridButton("Say Upper Diagonal"),
                        gridButton("Say Lower Diagonal"),
                        gridButton("Say Knight Moves"),
                        gridButton("Say Current Position"),
                        gridButton("Say All Board"),
                        gridButton("Say Machine Move"),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
// Top control row buttons
  Widget controlButton(String label) {
    return ElevatedButton(
      onPressed: () {
        // TODO: Add functionality later
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[300],
        foregroundColor: Colors.black,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero, // Rectangle shape
        ),
      ),
      child: Text(label),
    );
  }

// Grid buttons
  Widget gridButton(String label) {
    return ElevatedButton(
      onPressed: () {
        // TODO: Add functionality later
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[200],
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero, // Rectangle shape
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13),
      ),
    );
  }

// Top control row buttons

}
